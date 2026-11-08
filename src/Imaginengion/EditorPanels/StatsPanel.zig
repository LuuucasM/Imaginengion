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
const BVH = @import("../Core/BVH.zig");
const ConflictReport = @import("../ECS/ConflictReport.zig");
const SelectedTag = @import("../ECSComponents/EComponents.zig").SelectedTag;

const StatsPanel = @This();

/// Where the window opens, from the middle of the editor UI, and how big it is
const AT = @import("../Math/MathTypes.zig").Vec2(f32){ .x = 300, .y = 100 };
const SIZE = @import("../Math/MathTypes.zig").Vec2(f32){ .x = 420, .y = 380 };

/// How often its lines are refreshed. A line that changes is laid out and drawn again, and the loop time changes every
/// pass of the loop, so refreshing every pass would cost more than most of what it shows
pub const REFRESH_SECONDS: f32 = 0.25;

/// How many systems the Conflicts section shows, those with the most hooks
const CONFLICT_LINES = 8;

/// One world's section: a line for each stat
const WorldLines = struct {
    Objects: Entity,
    Quads: Entity,
    Glyphs: Entity,
    Shadings: Entity,
    /// the BVH over each layer's shapes: how deep a ray walks down it
    OverlayBVH: Entity,
    GameBVH: Entity,
    /// how good each tree is (BVH.TreeStats.Cost): lower is better for the same shapes
    BVHCosts: Entity,
    /// the world's own trees (WorldBVH), every scene in them, built once a frame
    WorldBVH: Entity,
    Entities: Entity,
};

mWindow: Entity = .uninit,
mLoopTime: Entity = .uninit,
mLoopRate: Entity = .uninit,
mFPS: Entity = .uninit,
/// The Conflicts section: the Measure checkbox's box (checked is SelectedTag on it), a total, and a line for each of
/// the systems with the most hooks, see ConflictReport
mMeasureBox: Entity = .uninit,
mConflictTotal: Entity = .uninit,
mConflictLines: [CONFLICT_LINES]Entity = undefined,
mGame: WorldLines = undefined,
mEditor: WorldLines = undefined,
mSimulate: WorldLines = undefined,
/// Since its lines were last refreshed. Starts due, so they show as soon as it opens
mSinceRefresh: f32 = REFRESH_SECONDS,

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
    try self.BuildConflicts(engine_context, window.Content, options);

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

/// Once a frame, before layout, while it is open: every REFRESH_SECONDS, the loop's time and rates, and the last rendered
/// frame's stats
pub fn Update(self: *StatsPanel, engine_context: *EngineContext, stats: *const EngineStats) !void {
    const zone = Tracy.ZoneInit("StatsPanel::Update", @src());
    defer zone.Deinit();
    if (!self.IsOpen()) {
        self.mSinceRefresh = REFRESH_SECONDS;
        return;
    }
    try self.SyncMeasuring(engine_context);
    self.mSinceRefresh += engine_context.mDT;
    if (self.mSinceRefresh < REFRESH_SECONDS) return;
    self.mSinceRefresh = 0;

    //a pass of the loop can skip rendering when the GPU is behind, so frames drawn are counted apart from it
    const dt = engine_context.mDT;
    try SetLine(engine_context, self.mLoopTime, "Loop time: {d:.0} us ({d:.5} s)", .{ std.time.us_per_s * dt, dt });
    try SetLine(engine_context, self.mLoopRate, "Loops/s: {d:.0}", .{stats.LoopRate.mRate});
    try SetLine(engine_context, self.mFPS, "FPS: {d:.0}", .{stats.FrameRate.mRate});
    try SetWorld(engine_context, self.mGame, stats.LastGameWorldStats);
    try SetWorld(engine_context, self.mEditor, stats.LastEditorWorldStats);
    try SetWorld(engine_context, self.mSimulate, stats.LastSimulateWorldStats);
    try self.SetConflicts(engine_context, &engine_context.mTransactions.mConflicts);
}

/// The Conflicts section: whether hooks would conflict if each system run's hooks ran in parallel (ConflictReport),
/// with the checkbox that turns measuring on
fn BuildConflicts(self: *StatsPanel, engine_context: *EngineContext, content: Entity, options: Widgets.Options) !void {
    const section = try Widgets.CollapsingHeader(engine_context, .{ .Entity = content }, "Conflicts (if hooks ran in parallel)", false, options);
    const lines: Widgets.Parent = .{ .Entity = section.Content.? };
    const measure_row = try Widgets.Checkbox(engine_context, lines, "Measure (ticking it starts fresh counts)", options);
    var row_children = measure_row.GetIterator(.Child);
    self.mMeasureBox = row_children.next().?;
    self.mConflictTotal = try Widgets.Label(engine_context, lines, "");
    for (&self.mConflictLines) |*line| line.* = try Widgets.Label(engine_context, lines, "");
}

/// Measuring follows the checkbox, and starts from nothing each time it is ticked
fn SyncMeasuring(self: *StatsPanel, engine_context: *EngineContext) !void {
    const conflicts = &engine_context.mTransactions.mConflicts;
    const ticked = self.mMeasureBox.HasComponent(SelectedTag);
    if (ticked == conflicts.mOn) return;
    if (ticked) conflicts.Clear(engine_context.EngineAllocator());
    conflicts.mOn = ticked;
}

/// The total and a line for each of the systems with the most hooks: how many of its hooks would conflict, how many
/// would run on their own, and the type most of its conflicts were on
fn SetConflicts(self: *StatsPanel, engine_context: *EngineContext, conflicts: *const ConflictReport) !void {
    const frame_allocator = engine_context.FrameAllocator();
    var hooks: u64 = 0;
    var conflicting: u64 = 0;
    var serial: u64 = 0;
    for (conflicts.mSystems.values()) |counts| {
        hooks += counts.mHooks;
        conflicting += counts.mConflicts;
        serial += counts.mSerial;
    }
    if (hooks == 0) {
        try SetLine(engine_context, self.mConflictTotal, "{s}", .{if (conflicts.mOn) "Measuring: no hooks have run yet" else "Not measuring"});
    } else {
        const percent = 100 * @as(f64, @floatFromInt(conflicting)) / @as(f64, @floatFromInt(hooks));
        try SetLine(engine_context, self.mConflictTotal, "{d} of {d} hooks would conflict ({d:.1}%), {d} would run on their own", .{ conflicting, hooks, percent, serial });
    }

    //the systems with the most hooks first
    const order = try frame_allocator.alloc(usize, conflicts.mSystems.count());
    for (order, 0..) |*index, i| index.* = i;
    const values = conflicts.mSystems.values();
    std.mem.sort(usize, order, values, struct {
        fn MoreHooks(all: []const ConflictReport.Counts, a: usize, b: usize) bool {
            return all[a].mHooks > all[b].mHooks;
        }
    }.MoreHooks);

    for (self.mConflictLines, 0..) |line, line_ind| {
        if (line_ind >= order.len) {
            try SetLine(engine_context, line, "", .{});
            continue;
        }
        const name = conflicts.mSystems.keys()[order[line_ind]];
        const counts = values[order[line_ind]];
        try SetLine(engine_context, line, "{s}: {d} of {d} would conflict, {d} on their own, {d} runs{s}{s}", .{
            ShortName(name),
            counts.mConflicts,
            counts.mHooks,
            counts.mSerial,
            counts.mBatches,
            if (counts.mTypes.count() > 0) ", mostly on " else "",
            MostCounted(counts),
        });
    }
}

/// A system's or type's name without what is in front of its last '.' or "::"
fn ShortName(name: []const u8) []const u8 {
    const after_colons = if (std.mem.lastIndexOf(u8, name, "::")) |at| name[at + 2 ..] else name;
    // a type name's dots, but not those inside the brackets of a script loop's name
    if (std.mem.indexOfScalar(u8, after_colons, '(') != null) return after_colons;
    return if (std.mem.lastIndexOfScalar(u8, after_colons, '.')) |at| after_colons[at + 1 ..] else after_colons;
}

/// The type most of a system's conflicts were on, "" if none
fn MostCounted(counts: ConflictReport.Counts) []const u8 {
    var best: []const u8 = "";
    var best_count: u64 = 0;
    for (counts.mTypes.keys(), counts.mTypes.values()) |type_name, count| {
        if (count > best_count) {
            best = ShortName(type_name);
            best_count = count;
        }
    }
    return best;
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
        .OverlayBVH = try Widgets.Label(engine_context, lines, ""),
        .GameBVH = try Widgets.Label(engine_context, lines, ""),
        .BVHCosts = try Widgets.Label(engine_context, lines, ""),
        .WorldBVH = try Widgets.Label(engine_context, lines, ""),
        .Entities = try Widgets.Label(engine_context, lines, ""),
    };
}

/// One layer's BVH as a line: how deep its deepest and its average leaf are, then its size
fn SetTreeLine(engine_context: *EngineContext, label: Entity, layer: []const u8, tree: BVH.TreeStats) !void {
    try SetLine(engine_context, label, "{s} BVH: depth {d} (avg {d:.1}), {d} nodes, {d} leaves of {d:.1}", .{
        layer,
        tree.Depth,
        tree.AverageLeafDepth(),
        tree.Nodes,
        tree.Leaves,
        tree.AverageLeafItems(),
    });
}

fn SetWorld(engine_context: *EngineContext, lines: WorldLines, stats: EngineStats.WorldStats) !void {
    const render = stats.mRenderStats;
    try SetLine(engine_context, lines.Objects, "Objects: {d}", .{render.TotalObjects});
    try SetLine(engine_context, lines.Quads, "Quads: {d}", .{render.OutputQuadNum});
    try SetLine(engine_context, lines.Glyphs, "Glyphs: {d}", .{render.OutputGlyphNum});
    try SetLine(engine_context, lines.Shadings, "Shadings: {d} (surface {d}, medium {d})", .{ render.Shadings.TotalShadings, render.Shadings.SurfShadings, render.Shadings.MedShadings });
    try SetTreeLine(engine_context, lines.OverlayBVH, "Overlay", render.OverlayBVH);
    try SetTreeLine(engine_context, lines.GameBVH, "Game", render.GameBVH);
    try SetLine(engine_context, lines.BVHCosts, "BVH cost: overlay {d:.1}, game {d:.1}", .{ render.OverlayBVH.Cost, render.GameBVH.Cost });
    const world_bvh = stats.mBVHStats;
    try SetLine(engine_context, lines.WorldBVH, "World BVH: overlay {d} items (depth {d}), game {d} items (depth {d})", .{
        world_bvh.Overlay.Items,
        world_bvh.Overlay.Depth,
        world_bvh.Game.Items,
        world_bvh.Game.Depth,
    });
    try SetLine(engine_context, lines.Entities, "Entities: {d}", .{stats.mECSStats.TotalEntities});
}

/// Puts a formatted line on a label, if it doesn't say that already
fn SetLine(engine_context: *EngineContext, label: Entity, comptime format: []const u8, args: anytype) !void {
    try WidgetActions.SetText(engine_context, label, try std.fmt.allocPrint(engine_context.FrameAllocator(), format, args));
}
