//! The save notice, in the editor's own UI: a small box in the bottom right corner saying what was just saved, or that
//! saving it failed, so a save is never silent. It stays for a moment, fades away and is collapsed until the next one,
//! so it costs the renderer nothing while it is hidden. A save over one still showing replaces its text and starts it
//! again.
const std = @import("std");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const Widgets = @import("../UI/Widgets.zig");
const WidgetActions = @import("../UI/WidgetActions.zig");
const UIManager = @import("../UI/UIManager.zig");
const Vec2 = @import("../Math/MathTypes.zig").Vec2;

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const LayoutComponent = EntityComponents.LayoutComponent;
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const SurfaceComponent = EntityComponents.SurfaceComponent;

const SaveNotice = @This();

/// How long it shows in full, then how long it takes to fade out, in seconds
const HOLD_TIME: f32 = 2;
const FADE_TIME: f32 = 1;
/// How far in from the corner it sits
const MARGIN: f32 = 12;
const BOTTOM_RIGHT = Vec2(f32){ .x = 1, .y = -1 };

mBox: Entity = .uninit,
mLabel: Entity = .uninit,
/// Seconds until it is gone, 0 while it is hidden
mTimeLeft: f32 = 0,

/// Builds it, hidden, at the top of `scene`, in front of the floating windows and menus
pub fn Build(engine_context: *EngineContext, scene: Scene) !SaveNotice {
    const zone = Tracy.ZoneInit("SaveNotice::Build", @src());
    defer zone.Deinit();
    const box = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    try box.SetTranslation(engine_context, .{ .x = 0, .y = 0, .z = Widgets.POPUP_DEPTH + 1 });
    try Widgets.AddQuad(engine_context, box, .{}, .{});
    _ = try box.AddComponent(engine_context, LayoutComponent{ .mDirection = .Row, .mPadding = .All(Widgets.PADDING * 2) });
    _ = try box.AddComponent(engine_context, LayoutItemComponent{
        .mPlacement = .{ .Anchored = .{ .Anchor = BOTTOM_RIGHT, .Pivot = BOTTOM_RIGHT, .Offset = .{ .x = -MARGIN, .y = MARGIN } } },
        .mCollapsed = true,
    });
    try UIManager.Style(engine_context, box, "Window");
    const label = try Widgets.Label(engine_context, .{ .Entity = box }, "");
    return .{ .mBox = box, .mLabel = label };
}

/// Shows `format` filled with `args`, fully, starting its time again
pub fn Show(self: *SaveNotice, engine_context: *EngineContext, comptime format: []const u8, args: anytype) !void {
    try WidgetActions.SetText(engine_context, self.mLabel, try std.fmt.allocPrint(engine_context.FrameAllocator(), format, args));
    try self.SetShown(engine_context, true);
    self.mTimeLeft = HOLD_TIME + FADE_TIME;
}

/// Once a frame, after the style pass, which would put its colors back to the theme's, and before layout, which hides it
pub fn Update(self: *SaveNotice, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("SaveNotice::Update", @src());
    defer zone.Deinit();
    if (self.mTimeLeft <= 0) return;
    self.mTimeLeft = @max(self.mTimeLeft - engine_context.mDT, 0);
    if (self.mTimeLeft == 0) return try self.SetShown(engine_context, false);
    const alpha = @min(self.mTimeLeft / FADE_TIME, 1);
    SetAlpha(self.mBox, alpha);
    SetAlpha(self.mLabel, alpha);
}

fn SetShown(self: SaveNotice, engine_context: *EngineContext, shown: bool) !void {
    const item = self.mBox.GetComponent(LayoutItemComponent).?;
    if (item.mCollapsed != shown) return;
    item.mCollapsed = !shown;
    try self.mBox.MarkLayoutDirty(engine_context);
}

/// How see-through its colors are, keeping what color they are
fn SetAlpha(entity: Entity, alpha: f32) void {
    const surface = entity.GetComponent(SurfaceComponent).?;
    surface.mTexOptions.mColor.w = alpha;
    surface.mTexOptions.mIsTransparent = alpha < 1;
    surface.mBorderColor.w = alpha;
}
