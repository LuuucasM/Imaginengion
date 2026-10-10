//! Styles: what a UI element's StyleComponent names, out of the current theme (ThemeAsset.zig), written into its
//! entity's quad and text. Part of the UIManager. Only the elements marked with StyleDirtyTag are restyled, when
//! something their style depends on changes (UIManager.MarkStyleDirty), and every one of them when the theme is new
//! or read again: a frame where the pointer moves onto a button restyles that button, not the whole UI. So a color
//! written into a styled entity by something else stays until its state next changes. The colors follow the state the entity is in, read from
//! its tags, highest first: disabled (it or anything it is inside has DisabledTag), pressed, hovered, focused, selected,
//! and otherwise normal. A state the style has no color for takes the normal one.
//! A styled quad or text with no texture of its own is filled plain, with a white texture, so its color is the theme's
//! alone: left with none, the renderer would fill it with the engine's default texture. Whatever a style leaves out is
//! left as the entity has it.
const std = @import("std");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const UIElement = @import("../ECSObjects/UIElement.zig");
const ThemeAsset = @import("../ECSComponents/Asset/ThemeAsset.zig");
const Texture2D = @import("../ECSComponents/Asset/Texture2D.zig");
const AssetHandle = @import("../ECSObjects/AssetHandle.zig");
const Vec4 = @import("../Math/MathTypes.zig").Vec4;

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const ShapeComponent = EntityComponents.ShapeComponent;
const SurfaceComponent = EntityComponents.SurfaceComponent;
const TextComponent = EntityComponents.TextComponent;
const PressedTag = EntityComponents.PressedTag;
const HoveredTag = EntityComponents.HoveredTag;
const FocusedTag = EntityComponents.FocusedTag;
const SelectedTag = EntityComponents.SelectedTag;
const StyleComponent = @import("../ECSComponents/UIComponents.zig").StyleComponent;
const StyleDirtyTag = @import("../ECSComponents/UIComponents.zig").StyleDirtyTag;
const DisabledTag = EntityComponents.DisabledTag;
const GameLayerTag = EntityComponents.GameLayerTag;
const PointerSystem = @import("../Pointer/PointerSystem.zig");

const StyleSystem = @This();

/// The state an entity is in, as far as its colors go
pub const State = enum { Normal, Hovered, Pressed, Focused, Selected, Disabled };

/// The tags an entity's state is read from (StateOf): adding or removing one has it styled again. DisabledTag has
/// everything inside it styled again too
pub const StateTags = [_]type{ PressedTag, HoveredTag, FocusedTag, SelectedTag, DisabledTag };

/// Whether `component_type` is one of StateTags
pub fn IsStateTag(comptime component_type: type) bool {
    inline for (StateTags) |tag| {
        if (component_type == tag) return true;
    }
    return false;
}

pub const empty: StyleSystem = .{};

/// The style names already warned about as missing from the theme, so a typo is logged once and not every frame
mWarned: std.StringHashMapUnmanaged(void) = .empty,

pub fn Deinit(self: *StyleSystem, engine_allocator: std.mem.Allocator) void {
    self.ClearWarnings(engine_allocator);
    self.mWarned.deinit(engine_allocator);
}

/// Forgets which missing styles were warned about, e.g. once another theme is current
pub fn ClearWarnings(self: *StyleSystem, engine_allocator: std.mem.Allocator) void {
    var iter = self.mWarned.keyIterator();
    while (iter.next()) |key| engine_allocator.free(key.*);
    self.mWarned.clearRetainingCapacity();
}

/// Once a frame, before layout (a font changing changes sizes): every styled element marked dirty, in every world, has
/// its entity take its style out of `theme`, and is no longer marked. `restyle_all` for every styled element instead,
/// for a theme that is new or was just read again
pub fn Update(self: *StyleSystem, engine_context: *EngineContext, theme: *const ThemeAsset, plain_texture: AssetHandle, restyle_all: bool) !void {
    const zone = Tracy.ZoneInit("StyleSystem::Update", @src());
    defer zone.Deinit();
    const ui_manager = &engine_context.mUIManager;
    const frame_allocator = engine_context.FrameAllocator();
    const element_ids = if (restyle_all)
        try ui_manager.GetGroup(frame_allocator, .{ .Component = StyleComponent })
    else
        try ui_manager.GetGroup(frame_allocator, .{ .Component = StyleDirtyTag });
    zone.Value(element_ids.items.len);
    for (element_ids.items) |element_id| {
        const element = UIElement{ .mID = element_id, .mManager = ui_manager };
        const entity = element.GetOwner();
        //no entity has taken it yet: it stays marked until one does
        if (!entity.IsActive()) continue;
        if (element.HasComponent(StyleDirtyTag)) try ui_manager.mECSManager.RemoveComponentSync(engine_context, element_id, @TypeOf(ui_manager.mECSManager).ComponentInd(StyleDirtyTag));

        const style_component = element.GetComponent(StyleComponent) orelse continue;
        const name = style_component.mStyle.items;
        const style = theme.GetStyle(name) orelse {
            try self.WarnMissing(engine_context.EngineAllocator(), name);
            continue;
        };
        try Apply(engine_context, entity, style.*, plain_texture);
    }
}

/// Gives a surface with no texture of its own the plain one, sampled only at its middle, so the edges of the texture
/// manager's slot it is in never blend in
fn FillPlain(texture: *AssetHandle, tex_options: *Texture2D.TexOptions, plain_texture: AssetHandle) void {
    if (texture.IsIDValid() or !plain_texture.IsIDValid()) return;
    plain_texture.RetainAsset();
    texture.* = plain_texture;
    tex_options.mTextureUV0 = .{ .x = 0.5, .y = 0.5 };
    tex_options.mTextureUV1 = .{ .x = 0.5, .y = 0.5 };
}

/// A surface's color, which is see-through for the renderer when it is at all
fn SetColor(surface: *SurfaceComponent, color: Vec4(f32)) void {
    surface.mTexOptions.mColor = color;
    surface.mTexOptions.mIsTransparent = color.w < 1;
}

/// The state `entity` is in, from its tags
pub fn StateOf(entity: Entity) State {
    if (PointerSystem.IsDisabled(entity)) return .Disabled;
    if (entity.HasComponent(PressedTag)) return .Pressed;
    if (entity.HasComponent(HoveredTag)) return .Hovered;
    if (entity.HasComponent(FocusedTag)) return .Focused;
    if (entity.HasComponent(SelectedTag)) return .Selected;
    return .Normal;
}

/// Writes `style`, for the state `entity` is in, into its surface, and its shape or text. A surface with no texture of
/// its own is given `plain_texture` (a white one) to fill with, unless that is uninit. A shape's surface takes the
/// background and border colors, a text's the text color
pub fn Apply(engine_context: *EngineContext, entity: Entity, style: ThemeAsset.Style, plain_texture: AssetHandle) !void {
    const state = StateOf(entity);
    //the style's sizes are in overlay units
    const unit = ThemeUnit(entity);
    const surface = entity.GetComponent(SurfaceComponent);
    if (surface) |surf| FillPlain(&surf.mTexture, &surf.mTexOptions, plain_texture);

    if (entity.GetComponent(ShapeComponent)) |shape| {
        if (surface) |surf| {
            if (ColorFor(style.Background, state)) |color| SetColor(surf, color);
            if (ColorFor(style.Border, state)) |color| surf.mBorderColor = color;
            if (style.BorderWidth) |width| surf.mBorderWidth = width * unit;
        }
        if (style.CornerRadius) |size| {
            const radius = size * unit;
            if (shape.GetQuad()) |quad| quad.CornerRadii = .{ .x = radius, .y = radius, .z = radius, .w = radius };
        }
    }

    if (entity.GetComponent(TextComponent)) |text| {
        if (surface) |surf| {
            if (ColorFor(style.Text, state)) |color| SetColor(surf, color);
        }
        //a different font or size is a different size of text, which layout has to fit again
        var resized = false;
        if (style.Font.IsIDValid() and text.mTextAssetHandle.mID != style.Font.mID) {
            text.mTextAssetHandle.ReleaseAsset();
            text.mTextAssetHandle = style.Font;
            text.mTextAssetHandle.RetainAsset();
            resized = true;
        }
        if (style.FontSize) |theme_size| {
            const size = theme_size * unit;
            if (text.mFontSize != size) {
                text.mFontSize = size;
                resized = true;
            }
        }
        if (resized) try entity.MarkLayoutDirty(engine_context);
    }
}

/// How many of `entity`'s own units one of a theme's sizes is: one in an overlay, whose units are the theme's, and
/// ThemeAsset.GAME_LAYER_UNIT in a game scene, in world units
pub fn ThemeUnit(entity: Entity) f32 {
    return if (entity.HasComponent(GameLayerTag)) ThemeAsset.GAME_LAYER_UNIT else 1;
}

/// The color for `state`, the normal one if it has none, or null if it hasn't that either
pub fn ColorFor(colors: ThemeAsset.StateColors, state: State) ?Vec4(f32) {
    const for_state = switch (state) {
        .Normal => colors.Normal,
        .Hovered => colors.Hovered,
        .Pressed => colors.Pressed,
        .Focused => colors.Focused,
        .Selected => colors.Selected,
        .Disabled => colors.Disabled,
    };
    return for_state orelse colors.Normal;
}

fn WarnMissing(self: *StyleSystem, engine_allocator: std.mem.Allocator, name: []const u8) !void {
    if (self.mWarned.contains(name)) return;
    std.log.warn("The current theme has no style called '{s}'", .{name});
    try self.mWarned.put(engine_allocator, try engine_allocator.dupe(u8, name), {});
}
