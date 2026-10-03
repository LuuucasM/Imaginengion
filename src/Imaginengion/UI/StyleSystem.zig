//! Styles: what a UI element's StyleComponent names, out of the current theme (ThemeAsset.zig), written into its
//! entity's quad and text every frame. Part of the UIManager. The colors follow the state the entity is in, read from
//! its tags, highest first: pressed, hovered, focused, selected, and otherwise normal. A state the style has no color
//! for takes the normal one. Whatever a style leaves out is left as the entity has it.
const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const UIElement = @import("../ECSObjects/UIElement.zig");
const ThemeAsset = @import("../ECSComponents/Asset/ThemeAsset.zig");
const Vec4 = @import("../Math/MathTypes.zig").Vec4;

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const QuadComponent = EntityComponents.QuadComponent;
const TextComponent = EntityComponents.TextComponent;
const PressedTag = EntityComponents.PressedTag;
const HoveredTag = EntityComponents.HoveredTag;
const FocusedTag = EntityComponents.FocusedTag;
const SelectedTag = EntityComponents.SelectedTag;
const StyleComponent = @import("../ECSComponents/UIComponents.zig").StyleComponent;

const StyleSystem = @This();

/// The state an entity is in, as far as its colors go
pub const State = enum { Normal, Hovered, Pressed, Focused, Selected };

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

/// Once a frame, before layout (a font changing changes sizes): every styled element's entity, in every world, takes
/// its style out of `theme`
pub fn Update(self: *StyleSystem, engine_context: *EngineContext, theme: *const ThemeAsset) !void {
    const ui_manager = &engine_context.mUIManager;
    const element_ids = try ui_manager.GetGroup(engine_context.FrameAllocator(), .{ .Component = StyleComponent });
    for (element_ids.items) |element_id| {
        const element = UIElement{ .mID = element_id, .mManager = ui_manager };
        const entity = element.GetOwner();
        if (!entity.IsActive()) continue;

        const name = element.GetComponent(StyleComponent).?.mStyle.items;
        const style = theme.GetStyle(name) orelse {
            try self.WarnMissing(engine_context.EngineAllocator(), name);
            continue;
        };
        try Apply(engine_context, entity, style.*);
    }
}

/// The state `entity` is in, from its tags
pub fn StateOf(entity: Entity) State {
    if (entity.HasComponent(PressedTag)) return .Pressed;
    if (entity.HasComponent(HoveredTag)) return .Hovered;
    if (entity.HasComponent(FocusedTag)) return .Focused;
    if (entity.HasComponent(SelectedTag)) return .Selected;
    return .Normal;
}

/// Writes `style`, for the state `entity` is in, into its quad and text
pub fn Apply(engine_context: *EngineContext, entity: Entity, style: ThemeAsset.Style) !void {
    const state = StateOf(entity);

    if (entity.GetComponent(QuadComponent)) |quad| {
        if (ColorFor(style.Background, state)) |color| {
            quad.mTexOptions.mColor = color;
            quad.mTexOptions.mIsTransparent = color.w < 1;
        }
        if (ColorFor(style.Border, state)) |color| quad.mBorderColor = color;
        if (style.BorderWidth) |width| quad.mBorderWidth = width;
        if (style.CornerRadius) |radius| quad.mCornerRadii = .{ .x = radius, .y = radius, .z = radius, .w = radius };
    }

    if (entity.GetComponent(TextComponent)) |text| {
        if (ColorFor(style.Text, state)) |color| {
            text.mTexOptions.mColor = color;
            text.mTexOptions.mIsTransparent = color.w < 1;
        }
        //a different font or size is a different size of text, which layout has to fit again
        var resized = false;
        if (style.Font.IsIDValid() and text.mTextAssetHandle.mID != style.Font.mID) {
            text.mTextAssetHandle.ReleaseAsset();
            text.mTextAssetHandle = style.Font;
            text.mTextAssetHandle.RetainAsset();
            resized = true;
        }
        if (style.FontSize) |size| {
            if (text.mFontSize != size) {
                text.mFontSize = size;
                resized = true;
            }
        }
        if (resized) try entity.MarkLayoutDirty(engine_context);
    }
}

/// The color for `state`, the normal one if it has none, or null if it hasn't that either
pub fn ColorFor(colors: ThemeAsset.StateColors, state: State) ?Vec4(f32) {
    const for_state = switch (state) {
        .Normal => colors.Normal,
        .Hovered => colors.Hovered,
        .Pressed => colors.Pressed,
        .Focused => colors.Focused,
        .Selected => colors.Selected,
    };
    return for_state orelse colors.Normal;
}

fn WarnMissing(self: *StyleSystem, engine_allocator: std.mem.Allocator, name: []const u8) !void {
    if (self.mWarned.contains(name)) return;
    std.log.warn("The current theme has no style called '{s}'", .{name});
    try self.mWarned.put(engine_allocator, try engine_allocator.dupe(u8, name), {});
}
