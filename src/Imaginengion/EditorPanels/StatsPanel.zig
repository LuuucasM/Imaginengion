//! The Stats panel, in the editor's own UI: a floating window showing how long a pass of the main loop took, how many
//! passes and how many drawn frames there were over the last second, and, for each world, what was rendered and how
//! many entities it has. Every world's stats are in a section of their own that starts folded: letters are shapes the
//! renderer has to draw, so a section only costs them while it is open. The Editor world's are the editor UI itself,
//! which is what counts towards the renderer's limit. The render stats are the last rendered frame's: they are only
//! complete once a frame has rendered, which is after the UI has been laid out, and a pass of the loop that skipped
//! rendering keeps showing the last frame that did.
const std = @import("std");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const EngineStats = @import("../Core/EngineStats.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const Widgets = @import("../UI/Widgets.zig");
const WidgetActions = @import("../UI/WidgetActions.zig");

const StatsPanel = @This();

/// Where the window opens, from the middle of the editor UI, and how big it is
const AT = @import("../Math/MathTypes.zig").Vec2(f32){ .x = 300, .y = 100 };
const SIZE = @import("../Math/MathTypes.zig").Vec2(f32){ .x = 300, .y = 320 };

/// One world's section: a line for each stat
const WorldLines = struct {
    Objects: Entity,
    Quads: Entity,
    Glyphs: Entity,
    Shadings: Entity,
    Entities: Entity,
};

mWindow: Entity = .uninit,
mLoopTime: Entity = .uninit,
mLoopRate: Entity = .uninit,
mFPS: Entity = .uninit,
mGame: WorldLines = undefined,
mEditor: WorldLines = undefined,
mSimulate: WorldLines = undefined,

/// Builds the window, closed, at the top of `scene`
pub fn Build(engine_context: *EngineContext, scene: Scene, options: Widgets.Options) !StatsPanel {
    const zone = Tracy.ZoneInit("StatsPanel::Build", @src());
    defer zone.Deinit();
    var self: StatsPanel = .{};
    const window = try Widgets.FloatingWindow(engine_context, scene, "Stats", SIZE, AT, options);
    self.mWindow = window.Window;
    const content: Widgets.Parent = .{ .Entity = window.Content };

    self.mLoopTime = try Widgets.Label(engine_context, content, "");
    self.mLoopRate = try Widgets.Label(engine_context, content, "");
    self.mFPS = try Widgets.Label(engine_context, content, "");
    self.mGame = try World(engine_context, window.Content, "Game World", options);
    self.mEditor = try World(engine_context, window.Content, "Editor World", options);
    self.mSimulate = try World(engine_context, window.Content, "Simulate World", options);

    try WidgetActions.CloseWindow(engine_context, self.mWindow);
    return self;
}

pub fn IsOpen(self: StatsPanel) bool {
    return WidgetActions.IsWindowOpen(self.mWindow);
}

/// Opens the window in front of the others, or closes it
pub fn Toggle(self: StatsPanel, engine_context: *EngineContext) !void {
    if (self.IsOpen()) {
        try WidgetActions.CloseWindow(engine_context, self.mWindow);
    } else {
        try WidgetActions.OpenWindow(engine_context, self.mWindow);
    }
}

/// Once a frame, before layout, while it is open: the loop's time and rates, and the last rendered frame's stats
pub fn Update(self: StatsPanel, engine_context: *EngineContext, stats: *const EngineStats) !void {
    const zone = Tracy.ZoneInit("StatsPanel::Update", @src());
    defer zone.Deinit();
    if (!self.IsOpen()) return;

    //a pass of the loop can skip rendering when the GPU is behind, so frames drawn are counted apart from it
    const dt = engine_context.mDT;
    try SetLine(engine_context, self.mLoopTime, "Loop time: {d:.0} us ({d:.5} s)", .{ std.time.us_per_s * dt, dt });
    try SetLine(engine_context, self.mLoopRate, "Loops/s: {d:.0}", .{stats.LoopRate.mRate});
    try SetLine(engine_context, self.mFPS, "FPS: {d:.0}", .{stats.FrameRate.mRate});
    try SetWorld(engine_context, self.mGame, stats.LastGameWorldStats);
    try SetWorld(engine_context, self.mEditor, stats.LastEditorWorldStats);
    try SetWorld(engine_context, self.mSimulate, stats.LastSimulateWorldStats);
}

/// A world's folded section, and its lines
fn World(engine_context: *EngineContext, content: Entity, title: []const u8, options: Widgets.Options) !WorldLines {
    const section = try Widgets.CollapsingHeader(engine_context, .{ .Entity = content }, title, false, options);
    const lines: Widgets.Parent = .{ .Entity = section.Content.? };
    return .{
        .Objects = try Widgets.Label(engine_context, lines, ""),
        .Quads = try Widgets.Label(engine_context, lines, ""),
        .Glyphs = try Widgets.Label(engine_context, lines, ""),
        .Shadings = try Widgets.Label(engine_context, lines, ""),
        .Entities = try Widgets.Label(engine_context, lines, ""),
    };
}

fn SetWorld(engine_context: *EngineContext, lines: WorldLines, stats: EngineStats.WorldStats) !void {
    const render = stats.mRenderStats;
    try SetLine(engine_context, lines.Objects, "Objects: {d}", .{render.TotalObjects});
    try SetLine(engine_context, lines.Quads, "Quads: {d}", .{render.OutputQuadNum});
    try SetLine(engine_context, lines.Glyphs, "Glyphs: {d}", .{render.OutputGlyphNum});
    try SetLine(engine_context, lines.Shadings, "Shadings: {d} (surface {d}, medium {d})", .{ render.Shadings.TotalShadings, render.Shadings.SurfShadings, render.Shadings.MedShadings });
    try SetLine(engine_context, lines.Entities, "Entities: {d}", .{stats.mECSStats.TotalEntities});
}

/// Puts a formatted line on a label, if it doesn't say that already
fn SetLine(engine_context: *EngineContext, label: Entity, comptime format: []const u8, args: anytype) !void {
    try WidgetActions.SetText(engine_context, label, try std.fmt.allocPrint(engine_context.FrameAllocator(), format, args));
}
