//! The Profiler panel, in the editor's own UI: a floating window showing the engine profiler's tree (Core/Profiler.zig),
//! a node per zone per place it was called from, each titled with how long it takes a pass of the loop over the passes
//! the profiler remembers: on average, the 99th percentile, the worst, its own time without the zones inside it, and how
//! many times it runs. Nodes are added as the profiler meets them and are never removed. Only the rows that can be seen
//! (every node above them open) are refreshed, every REFRESH_SECONDS: letters are shapes the renderer has to draw, so a
//! folded part of the tree costs nothing. A node that starts a world's part of the tree (Profiler.StartsWorld) has the
//! world's name in front, and the line above the tree adds up each world's time.
const std = @import("std");
const Tracy = @import("../Core/Tracy.zig");
const Profiler = @import("../Core/Profiler.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const Widgets = @import("../UI/Widgets.zig");
const WidgetActions = @import("../UI/WidgetActions.zig");
const UIManager = @import("../UI/UIManager.zig");
const LayoutItemComponent = @import("../ECSComponents/EComponents.zig").LayoutItemComponent;
const Vec2 = @import("../Math/MathTypes.zig").Vec2;

const ProfilerPanel = @This();

/// Where the window opens, from the middle of the editor UI, and how big it is
const AT = Vec2(f32){ .x = 0, .y = 50 };
const SIZE = Vec2(f32){ .x = 720, .y = 520 };

/// How often the rows are refreshed, as the Stats panel's are
pub const REFRESH_SECONDS: f32 = 0.25;

/// A profiler node's row
const Row = struct {
    Node: Widgets.Fold,
    /// its title, the line its numbers are on
    Title: Entity,
};

mWindow: Entity = .uninit,
mContent: Entity = .uninit,
/// The line above the tree saying what the numbers are
mNote: Entity = .uninit,
/// Under it, how long each world takes a pass (Profiler.WorldAverage)
mWorlds: Entity = .uninit,
/// Made the first time the window is open with the profiler running
mTree: ?Entity = null,
/// A row per profiler node, at the node's index. The root's is never used: its children go straight in the tree
mRows: std.ArrayList(Row) = .empty,
/// Since the rows were last refreshed. Starts due, so they show as soon as it opens
mSinceRefresh: f32 = REFRESH_SECONDS,
mOptions: Widgets.Options = .{},

/// Builds the window, closed and empty, at the top of `scene`
pub fn Build(engine_context: *EngineContext, scene: Scene, options: Widgets.Options) !ProfilerPanel {
    const zone = Tracy.ZoneInit("ProfilerPanel::Build", @src());
    defer zone.Deinit();
    const window = try Widgets.FloatingWindow(engine_context, scene, "Profiler", SIZE, AT, options);
    const self = ProfilerPanel{
        .mWindow = window.Window,
        .mContent = window.Content,
        .mNote = try Widgets.Label(engine_context, .{ .Entity = window.Content }, ""),
        .mWorlds = try Widgets.Label(engine_context, .{ .Entity = window.Content }, ""),
        .mOptions = options,
    };
    try WidgetActions.CloseWindow(engine_context, self.mWindow);
    return self;
}

pub fn Deinit(self: *ProfilerPanel, keep_allocator: std.mem.Allocator) void {
    self.mRows.deinit(keep_allocator);
}

pub fn IsOpen(self: ProfilerPanel) bool {
    return WidgetActions.IsWindowOpen(self.mWindow);
}

/// Opens the window in front of the others, or closes it
pub fn Toggle(self: ProfilerPanel, engine_context: *EngineContext) !void {
    if (self.IsOpen()) {
        try WidgetActions.CloseWindow(engine_context, self.mWindow);
    } else {
        try WidgetActions.OpenWindow(engine_context, self.mWindow);
    }
}

/// Once a frame, before layout, while it is open: every REFRESH_SECONDS, rows for the nodes `profiler` has met since,
/// and the numbers on every row that can be seen
pub fn Update(self: *ProfilerPanel, engine_context: *EngineContext, profiler: *const Profiler) !void {
    const zone = Tracy.ZoneInit("ProfilerPanel::Update", @src());
    defer zone.Deinit();
    if (!self.IsOpen()) {
        self.mSinceRefresh = REFRESH_SECONDS;
        return;
    }
    self.mSinceRefresh += engine_context.mDT;
    if (self.mSinceRefresh < REFRESH_SECONDS) return;
    self.mSinceRefresh = 0;

    if (!profiler.IsRunning()) {
        try WidgetActions.SetText(engine_context, self.mNote, "Not measuring");
        return;
    }
    try SetLine(engine_context, self.mNote, "A pass of the loop, over the last {d}: average, 99th percentile, worst, own time (without the zones inside), times run", .{profiler.LoopsKept()});

    try self.SetWorlds(engine_context, profiler);
    try self.AddRows(engine_context, profiler);
    try self.Refresh(engine_context, profiler);
}

/// Each world that ran anything, and its time a pass on average
fn SetWorlds(self: *ProfilerPanel, engine_context: *EngineContext, profiler: *const Profiler) !void {
    var line: std.Io.Writer.Allocating = .init(engine_context.mEditorWorld.Scratch());
    try line.writer.writeAll("Each world, a pass on average:");
    var any = false;
    for (1..EngineContext.WORLD_NAMES.len + 1) |tag| {
        const world: Profiler.World = @intCast(tag);
        if (!RanOn(profiler, world)) continue;
        try line.writer.print("{s} {s} {d:.1} us", .{ if (any) "," else "", EngineContext.WorldName(world), Micros(profiler.WorldAverage(world)) });
        any = true;
    }
    if (!any) try line.writer.writeAll(" none measured yet");
    try WidgetActions.SetText(engine_context, self.mWorlds, line.written());
}

fn RanOn(profiler: *const Profiler, world: Profiler.World) bool {
    for (1..profiler.NodeCount()) |node_ind| {
        if (profiler.GetNode(@intCast(node_ind)).mWorld == world) return true;
    }
    return false;
}

/// A node's name, with its world's in front when it starts that world's part of the tree
fn Title(engine_context: *EngineContext, profiler: *const Profiler, node: Profiler.NodeIndex) ![]const u8 {
    if (!profiler.StartsWorld(node)) return profiler.Name(node);
    return try std.fmt.allocPrint(engine_context.mEditorWorld.Scratch(), "[{s}] {s}", .{ EngineContext.WorldName(profiler.GetNode(node).mWorld), profiler.Name(node) });
}

/// The row of each node met since the last refresh, under its parent's row. Nodes come after their parents, so the
/// parent's row is always there already. The top ones start open, the rest folded
fn AddRows(self: *ProfilerPanel, engine_context: *EngineContext, profiler: *const Profiler) !void {
    const keep_allocator = engine_context.mEditorWorld.Keep();
    if (self.mTree == null) {
        //the root's row is the tree itself, so the top nodes go in it like any other node goes in its parent's content
        const tree = try Widgets.Tree(engine_context, .{ .Entity = self.mContent });
        self.mTree = tree;
        try self.mRows.append(keep_allocator, .{ .Node = .{ .Node = tree, .Header = tree, .Content = tree }, .Title = .uninit });
    }
    for (self.mRows.items.len..profiler.NodeCount()) |node_ind| {
        const node: Profiler.NodeIndex = @intCast(node_ind);
        const parent = profiler.GetNode(node).mParent;
        const fold = try Widgets.TreeNode(engine_context, .{ .Entity = self.mRows.items[parent].Node.Content.? }, try Title(engine_context, profiler, node), .{
            .Open = parent == Profiler.ROOT,
            .StockScripts = self.mOptions.StockScripts,
        });
        try self.mRows.append(keep_allocator, .{ .Node = fold, .Title = UIManager.LabelOf(fold.Header).? });
    }
}

/// The numbers on every row whose parents are all open
fn Refresh(self: *ProfilerPanel, engine_context: *EngineContext, profiler: *const Profiler) !void {
    const rows = self.mRows.items;
    const shown = try engine_context.mEditorWorld.Scratch().alloc(bool, rows.len);
    shown[Profiler.ROOT] = true;
    for (rows[1..], 1..) |row, node_ind| {
        const parent = profiler.GetNode(@intCast(node_ind)).mParent;
        shown[node_ind] = shown[parent] and (parent == Profiler.ROOT or !IsFolded(rows[parent]));
        if (!shown[node_ind]) continue;

        const node: Profiler.NodeIndex = @intCast(node_ind);
        const summary = profiler.Summarize(node);
        var inside: i96 = 0;
        var children = profiler.Children(node);
        while (children.next()) |child| inside += profiler.Average(child).toNanoseconds();
        const own: std.Io.Duration = .fromNanoseconds(@max(0, summary.Avg.toNanoseconds() - inside));
        try SetLine(engine_context, row.Title, "{s}   {d:.1} / {d:.1} / {d:.1} us   own {d:.1} us   x{d:.1}", .{
            try Title(engine_context, profiler, node),
            Micros(summary.Avg),
            Micros(summary.P99),
            Micros(summary.Max),
            Micros(own),
            summary.Calls,
        });
    }
}

fn IsFolded(row: Row) bool {
    const content = row.Node.Content orelse return true;
    const item = content.GetComponent(LayoutItemComponent) orelse return false;
    return item.mCollapsed;
}

fn Micros(duration: std.Io.Duration) f64 {
    return @as(f64, @floatFromInt(duration.toNanoseconds())) / std.time.ns_per_us;
}

/// Puts a formatted line on a label, if it doesn't say that already
fn SetLine(engine_context: *EngineContext, label: Entity, comptime format: []const u8, args: anytype) !void {
    try WidgetActions.SetText(engine_context, label, try std.fmt.allocPrint(engine_context.mEditorWorld.Scratch(), format, args));
}
