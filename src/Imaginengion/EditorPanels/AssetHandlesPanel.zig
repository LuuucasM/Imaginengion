//! The Asset Handles panel, in the editor's own UI: a floating window listing every asset the asset manager has loaded,
//! one line each, its handle and its path. The list is checked against the asset manager every frame it is open, and
//! lines are only made or deleted when the number of assets changes. Long paths are cut off at the window's edge, and a
//! long list scrolls.
const std = @import("std");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const Widgets = @import("../UI/Widgets.zig");
const WidgetActions = @import("../UI/WidgetActions.zig");
const FileMetaData = @import("../ECSComponents/Asset/FileMetaData.zig");
const MathTypes = @import("../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;

const AssetHandlesPanel = @This();

/// Where the window opens, from the middle of the editor UI, and how big it is
const AT = Vec2(f32){ .x = -200, .y = 100 };
const SIZE = Vec2(f32){ .x = 420, .y = 360 };

mWindow: Entity = .uninit,
/// A line per asset, in the asset manager's order
mLines: Entity = .uninit,

/// Builds the window, closed, at the top of `scene`
pub fn Build(engine_context: *EngineContext, scene: Scene, options: Widgets.Options) !AssetHandlesPanel {
    const zone = Tracy.ZoneInit("AssetHandlesPanel::Build", @src());
    defer zone.Deinit();
    const window = try Widgets.FloatingWindow(engine_context, scene, "Asset Handles", SIZE, AT, options);
    const self = AssetHandlesPanel{ .mWindow = window.Window, .mLines = try Widgets.Lines(engine_context, .{ .Entity = window.Content }) };
    try WidgetActions.CloseWindow(engine_context, self.mWindow);
    return self;
}

pub fn IsOpen(self: AssetHandlesPanel) bool {
    return WidgetActions.IsWindowOpen(self.mWindow);
}

/// Opens the window in front of the others, or closes it
pub fn Toggle(self: AssetHandlesPanel, engine_context: *EngineContext) !void {
    if (self.IsOpen()) {
        try WidgetActions.CloseWindow(engine_context, self.mWindow);
    } else {
        try WidgetActions.OpenWindow(engine_context, self.mWindow);
    }
}

/// Once a frame, before layout, while it is open: a line for each asset loaded right now
pub fn Update(self: AssetHandlesPanel, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("AssetHandlesPanel::Update", @src());
    defer zone.Deinit();
    if (!self.IsOpen()) return;

    const frame_allocator = engine_context.FrameAllocator();
    const asset_ids = try engine_context.mAssetManager.GetGroup(frame_allocator, .{ .Component = FileMetaData });
    const lines = try frame_allocator.alloc([]const u8, asset_ids.items.len);
    for (asset_ids.items, lines) |asset_id, *line| {
        const file_data = engine_context.mAssetManager.GetFileMetaData(asset_id);
        line.* = try std.fmt.allocPrint(frame_allocator, "{d}: {s}", .{ asset_id, file_data.mRelPath.items });
    }
    try Widgets.SyncLines(engine_context, self.mLines, lines);
}
