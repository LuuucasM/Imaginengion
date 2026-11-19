//! The Profiler panel: a floating window, in the editor's own UI and in a game built with -Dstats (Programs/GameStats.zig),
//! showing the engine profiler's tree (Core/Profiler.zig),
//! a node per zone per place it was called from, each titled with how long it takes a pass of the loop over the passes
//! the profiler remembers: on average, the 99th percentile, the worst, its own time without the zones inside it, and how
//! many times it runs. Nodes are added as the profiler meets them and are never removed. Only the rows that can be seen
//! (every node above them open) are refreshed, every REFRESH_SECONDS: letters are shapes the renderer has to draw, so a
//! folded part of the tree costs nothing. A node that starts a world's part of the tree (Profiler.StartsWorld) has the
//! world's name in front, and the line above the tree adds up each world's time.
//!
//! Beside it, in a section of its own, the memory tree (Allocators.MemoryNode): Application at the top, then the engine
//! and the program, then the worlds and the engine's managers, then their ECSs and each ECS's component arrays, each
//! row with what it and everything under it holds now. It doesn't need the profiler running, and is built again
//! whenever a node comes or goes.
//!
//! Then the video memory tree: the driver's count of all of it at the top (PlatformUtils.VideoMemory), then what the
//! engine made (GPUAllocator), by owner and then by what each resource is for (GPUAllocator.Group), and what it didn't
//! (the swapchain, pipelines, the driver's own). Built again whenever a group is met for the first time. Beside it, how
//! much of the texture atlas is in use, by size of texture (TextureManager.GetUsage).
//!
//! Then the last rendered frame's stats for each world (EngineStats): what was drawn, the BVHs and how many entities
//! there are, a folded section per world, the editor's three worlds in the editor and the Game world's in a game. And
//! the Conflicts section: whether hooks would conflict if each system run's hooks ran in parallel (ConflictReport), with
//! the checkbox that turns measuring on. Above every section, frames and passes of the loop a second.
const std = @import("std");
const Tracy = @import("../Core/Tracy.zig");
const Profiler = @import("../Core/Profiler.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const WorldManager = @import("../Core/WorldManager.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const Widgets = @import("../UI/Widgets.zig");
const WidgetActions = @import("../UI/WidgetActions.zig");
const UIManager = @import("../UI/UIManager.zig");
const LayoutItemComponent = @import("../ECSComponents/EComponents.zig").LayoutItemComponent;
const Vec2 = @import("../Math/MathTypes.zig").Vec2;
const MemoryNode = @import("../Core/Allocators.zig").MemoryNode;
const GPUAllocator = @import("../Core/GPUAllocator.zig");
const Bytes = @import("../Core/Allocators.zig").Bytes;
const EngineStats = @import("../Core/EngineStats.zig");
const BVH = @import("../Core/BVH.zig");
const ConflictReport = @import("../ECS/ConflictReport.zig");
const SelectedTag = @import("../ECSComponents/EComponents.zig").SelectedTag;
const TextureManager = @import("../TextureManager/TextureManager.zig");

const ProfilerPanel = @This();

/// Where the window opens, from the middle of the editor UI, and how big it is
const AT = Vec2(f32){ .x = 0, .y = 50 };
const SIZE = Vec2(f32){ .x = 900, .y = 620 };

/// How often the rows are refreshed. A line that changes is laid out and drawn again, so refreshing every pass of the
/// loop would cost more than most of what it shows
pub const REFRESH_SECONDS: f32 = 0.25;

/// How many systems the Conflicts section shows, those with the most hooks
const CONFLICT_LINES = 8;

/// Which program it is in, which decides the worlds whose rendering it shows
pub const Shows = enum {
    /// the Game, Editor and Simulate worlds
    Editor,
    /// the Game world only, the one a game has
    Game,
};

/// One world's rendering section: a line for each stat
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

/// A profiler node's row
const Row = struct {
    Node: Widgets.Fold,
    /// its title, the line its numbers are on
    Title: Entity,
};

/// What a row of the video memory tree is for
const VideoRowOf = union(enum) {
    /// everything, as the driver counts it
    All,
    /// what the engine made
    Ours,
    /// what it didn't: the driver's count less the engine's
    Rest,
    Owner: GPUAllocator.Owner,
    /// a GPUAllocator.Group, by its index
    Group: u32,
    /// how much of the texture atlas is in use
    Atlas,
    /// one size class's use of it (AtlasHandle), by the class
    AtlasBin: u8,
    /// what one owner's slots take of it
    AtlasOwner: GPUAllocator.Owner,
};

/// A video memory tree node's row
const VideoRow = struct {
    Of: VideoRowOf,
    Title: Entity,
};

/// A memory tree node's row
const MemoryRow = struct {
    Node: *MemoryNode,
    Fold: Widgets.Fold,
    Title: Entity,
    /// the row of the node above it, null for the top
    Parent: ?usize,
};

mWindow: Entity = .uninit,
/// Above the sections: frames drawn and passes of the loop a second
mRates: Entity = .uninit,
/// The Time section's content, where the time tree goes
mContent: Entity = .uninit,
/// The Memory section's content, its note and the memory tree
mMemoryContent: Entity = .uninit,
mMemoryNote: Entity = .uninit,
/// The game's memory against the target platform's budgets (TargetPlatforms), under each memory section's note
mCPUBudget: Entity = .uninit,
mVideoBudget: Entity = .uninit,
/// Which program it is in: what the budget lines are of
mShows: Shows = .Editor,
/// The Video memory section's content, where its tree goes
mVideoContent: Entity = .uninit,
/// Made the first time the window is open, and again when a GPU resource group is met for the first time
mVideoTree: ?Entity = null,
mVideoRows: std.ArrayList(VideoRow) = .empty,
/// How many groups GPUAllocator had when the video rows were built
mVideoGroups: usize = 0,
/// Which owners had atlas slots when the video rows were built, a bit each
mVideoAtlasOwners: u32 = 0,
/// Made the first time the window is open, and again when the tree changes (mMemoryVersion)
mMemoryTree: ?Entity = null,
/// A row per memory node, parents before their children
mMemoryRows: std.ArrayList(MemoryRow) = .empty,
/// Allocators.gTreeVersion when the memory rows were built
mMemoryVersion: u32 = 0,
/// The line above the tree saying what the numbers are
mNote: Entity = .uninit,
/// Under it, how long each world takes a pass (Profiler.WorldAverage)
mWorlds: Entity = .uninit,
/// Made the first time the window is open with the profiler running
mTree: ?Entity = null,
/// A row per profiler node, at the node's index. The root's is never used: its children go straight in the tree
mRows: std.ArrayList(Row) = .empty,
/// The Rendering section: a folded section of lines for each world it shows (Shows)
mGame: WorldLines = undefined,
mEditor: ?WorldLines = null,
mSimulate: ?WorldLines = null,
/// The Conflicts section: the Measure checkbox's box (checked is SelectedTag on it), a total, and a line for each of
/// the systems with the most hooks, see ConflictReport
mMeasureBox: Entity = .uninit,
mConflictTotal: Entity = .uninit,
mConflictLines: [CONFLICT_LINES]Entity = undefined,
/// Since the rows were last refreshed. Starts due, so they show as soon as it opens
mSinceRefresh: f32 = REFRESH_SECONDS,
mOptions: Widgets.Options = .{},

/// Builds the window, closed and empty, at the top of `scene`
pub fn Build(engine_context: *EngineContext, scene: Scene, shows: Shows, options: Widgets.Options) !ProfilerPanel {
    const zone = Tracy.ZoneInit("ProfilerPanel::Build", @src());
    defer zone.Deinit();
    const window = try Widgets.FloatingWindow(engine_context, scene, "Profiler", SIZE, AT, options);
    const rates = try Widgets.Label(engine_context, .{ .Entity = window.Content }, "");
    const time = try Widgets.CollapsingHeader(engine_context, .{ .Entity = window.Content }, "Time", true, options);
    const memory = try Widgets.CollapsingHeader(engine_context, .{ .Entity = window.Content }, "Memory", true, options);
    const video = try Widgets.CollapsingHeader(engine_context, .{ .Entity = window.Content }, "Video memory", true, options);
    var self = ProfilerPanel{
        .mWindow = window.Window,
        .mRates = rates,
        .mContent = time.Content.?,
        .mNote = try Widgets.Label(engine_context, .{ .Entity = time.Content.? }, ""),
        .mWorlds = try Widgets.Label(engine_context, .{ .Entity = time.Content.? }, ""),
        .mMemoryContent = memory.Content.?,
        .mMemoryNote = try Widgets.Label(engine_context, .{ .Entity = memory.Content.? }, "Held now, everything under each included: total (structs and what they hold), held, of it its own, the structs' own bytes, allocations, Scratch taken the last pass"),
        .mCPUBudget = try Widgets.Label(engine_context, .{ .Entity = memory.Content.? }, ""),
        .mVideoContent = video.Content.?,
        .mVideoBudget = try Widgets.Label(engine_context, .{ .Entity = video.Content.? }, ""),
        .mShows = shows,
        .mOptions = options,
    };

    const rendering = try Widgets.CollapsingHeader(engine_context, .{ .Entity = window.Content }, "Rendering (the last rendered frame)", false, options);
    self.mGame = try WorldSection(engine_context, rendering.Content.?, "Game World", options);
    if (shows == .Editor) {
        self.mEditor = try WorldSection(engine_context, rendering.Content.?, "Editor World", options);
        self.mSimulate = try WorldSection(engine_context, rendering.Content.?, "Simulate World", options);
    }
    try self.BuildConflicts(engine_context, window.Content, options);

    try WidgetActions.CloseWindow(engine_context, self.mWindow);
    return self;
}

pub fn Deinit(self: *ProfilerPanel, keep_allocator: std.mem.Allocator) void {
    self.mRows.deinit(keep_allocator);
    self.mMemoryRows.deinit(keep_allocator);
    self.mVideoRows.deinit(keep_allocator);
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
    try self.SyncMeasuring(engine_context);
    self.mSinceRefresh += engine_context.mDT;
    if (self.mSinceRefresh < REFRESH_SECONDS) return;
    self.mSinceRefresh = 0;

    //a pass of the loop can skip rendering when the GPU is behind, so frames drawn are counted apart from it
    const stats = &engine_context.mEngineStats;
    try SetLine(engine_context, self.mRates, "{d:.0} FPS   {d:.0} passes of the loop a second", .{ stats.FrameRate.mRate, stats.LoopRate.mRate });
    try self.UpdateMemory(engine_context);
    try self.UpdateVideo(engine_context);
    try SetWorld(engine_context, self.mGame, stats.LastGameWorldStats);
    if (self.mEditor) |lines| try SetWorld(engine_context, lines, stats.LastEditorWorldStats);
    if (self.mSimulate) |lines| try SetWorld(engine_context, lines, stats.LastSimulateWorldStats);
    try self.SetConflicts(engine_context, &engine_context.mTransactions.mConflicts);

    if (!profiler.IsRunning()) {
        try WidgetActions.SetText(engine_context, self.mNote, "Not measuring");
        return;
    }
    try SetLine(engine_context, self.mNote, "A pass of the loop, over the last {d}: average, 99th percentile, worst, own time (without the zones inside), times run", .{profiler.LoopsKept()});

    try self.SetWorlds(engine_context, profiler);
    try self.AddRows(engine_context, profiler);
    try self.Refresh(engine_context, profiler);
}

/// The memory tree's rows: built again if a node came or went, then the numbers on every row that can be seen
fn UpdateMemory(self: *ProfilerPanel, engine_context: *EngineContext) !void {
    const platforms = &engine_context.mTargetPlatforms;
    try self.SetBudgetLine(engine_context, self.mCPUBudget, platforms.mLastUsage.CPU, platforms.Target().mCPUMemoryMB);
    const root = engine_context._Internal.Memory.Root();
    const version = @import("../Core/Allocators.zig").gTreeVersion;
    if (self.mMemoryTree == null or self.mMemoryVersion != version) {
        if (self.mMemoryTree) |tree| try Widgets.Remove(engine_context, tree, &.{});
        self.mMemoryRows.clearRetainingCapacity();
        const tree = try Widgets.Tree(engine_context, .{ .Entity = self.mMemoryContent });
        self.mMemoryTree = tree;
        try self.AddMemoryRows(engine_context, root, tree, null, 0);
        self.mMemoryVersion = version;
    }

    //parents come before their children, so whether a parent's row can be seen is known by the time its children's are
    const rows = self.mMemoryRows.items;
    const shown = try engine_context.ProgramScratch().alloc(bool, rows.len);
    for (rows, 0..) |row, row_ind| {
        shown[row_ind] = if (row.Parent) |parent| shown[parent] and !IsFolded(.{ .Node = rows[parent].Fold, .Title = rows[parent].Title }) else true;
        if (!shown[row_ind]) continue;
        const total = row.Node.Totals();
        const own = row.Node.mCounts.Read();
        try SetLine(engine_context, row.Title, "{s}   {f}   held {f} ({f} its own)   structs {f}   {d} allocs   Scratch {f}", .{
            row.Node.mName,
            Bytes{ .mBytes = total.Bytes() },
            Bytes{ .mBytes = total.Held },
            Bytes{ .mBytes = own.KeepBytes },
            Bytes{ .mBytes = @intCast(total.Size) },
            total.Allocs,
            Bytes{ .mBytes = total.Scratch },
        });
    }
}

/// A row for `node` under `parent`, then rows for everything under it. The top two levels start open
fn AddMemoryRows(self: *ProfilerPanel, engine_context: *EngineContext, node: *MemoryNode, parent: Entity, parent_row: ?usize, depth: usize) !void {
    const fold = try Widgets.TreeNode(engine_context, .{ .Entity = parent }, node.mName, .{
        .Open = depth < 2,
        .StockScripts = self.mOptions.StockScripts,
    });
    const row = self.mMemoryRows.items.len;
    try self.mMemoryRows.append(engine_context.ProgramKeep(), .{ .Node = node, .Fold = fold, .Title = UIManager.LabelOf(fold.Header).?, .Parent = parent_row });
    var children = node.Children();
    while (children.next()) |child| try self.AddMemoryRows(engine_context, child, fold.Content.?, row, depth + 1);
}

/// What the game is using of one of the target platform's budgets, and what that is of: in the editor only as near as
/// it can tell what is the game's, in a game all of it
fn SetBudgetLine(self: *ProfilerPanel, engine_context: *EngineContext, label: Entity, bytes: u64, budget_mb: u32) !void {
    const budget: u64 = @as(u64, budget_mb) * 1024 * 1024;
    const percent = if (budget == 0) 0 else 100 * bytes / budget;
    try SetLine(engine_context, label, "Budget ({s}): {f} of {f}, {d}%{s}   ({s})", .{
        engine_context.mTargetPlatforms.GetName(engine_context.mTargetPlatforms.mTarget),
        Bytes{ .mBytes = @intCast(bytes) },
        Bytes{ .mBytes = @intCast(budget) },
        percent,
        if (bytes > budget) ", over" else "",
        switch (self.mShows) {
            .Editor => "the game's world and loaded objects, as near as the editor can tell",
            .Game => "the whole game",
        },
    });
}

/// The video memory tree's rows: built again if a group was met since, then the numbers on each. It is small, so every
/// row is refreshed whether it can be seen or not
fn UpdateVideo(self: *ProfilerPanel, engine_context: *EngineContext) !void {
    const platforms = &engine_context.mTargetPlatforms;
    try self.SetBudgetLine(engine_context, self.mVideoBudget, platforms.mLastUsage.Video, platforms.Target().mVideoMemoryMB);
    const gpu = &engine_context.mGPUAllocator;
    if (self.mVideoTree == null or self.mVideoGroups != gpu.mGroups.items.len or self.mVideoAtlasOwners != AtlasOwners(gpu)) try self.BuildVideoRows(engine_context);

    const driver = gpu.mDriver.Read();
    const ours = gpu.TotalBytes();
    const atlas = engine_context.mRenderer.mTextureManager.GetUsage();
    for (self.mVideoRows.items) |row| {
        switch (row.Of) {
            .All => if (driver) |usage| {
                try SetLine(engine_context, row.Title, "Video memory   {f}   {f} on the GPU (of a {f} budget), {f} shared", .{
                    Bytes{ .mBytes = @intCast(usage.Used + usage.Shared) },
                    Bytes{ .mBytes = @intCast(usage.Used) },
                    Bytes{ .mBytes = @intCast(usage.Budget) },
                    Bytes{ .mBytes = @intCast(usage.Shared) },
                });
            } else try SetLine(engine_context, row.Title, "Video memory   {f}   (the driver's count can't be read here)", .{Bytes{ .mBytes = @intCast(ours) }}),
            .Ours => try SetLine(engine_context, row.Title, "Made by the engine   {f}", .{Bytes{ .mBytes = @intCast(ours) }}),
            .Rest => if (driver) |usage| {
                try SetLine(engine_context, row.Title, "Not made by the engine: the swapchain, pipelines, the driver's own   {f}", .{
                    Bytes{ .mBytes = @as(i64, @intCast(usage.Used + usage.Shared)) - @as(i64, @intCast(ours)) },
                });
            } else try SetLine(engine_context, row.Title, "Not made by the engine: the swapchain, pipelines, the driver's own   can't be read here", .{}),
            .Owner => |owner| {
                const counts = gpu.CountsOf(owner);
                try SetLine(engine_context, row.Title, "{s}   {f}   peak {f}", .{ OwnerName(owner), Bytes{ .mBytes = @intCast(counts.Bytes) }, Bytes{ .mBytes = @intCast(counts.Peak) } });
            },
            .Group => |group_ind| {
                const group = gpu.mGroups.items[group_ind];
                try SetLine(engine_context, row.Title, "{s}   {f}   peak {f}   {s} x{d}", .{ group.Name, Bytes{ .mBytes = @intCast(group.Bytes) }, Bytes{ .mBytes = @intCast(group.Peak) }, group.Kind.Title(), group.Count });
            },
            .AtlasOwner => |owner| try SetLine(engine_context, row.Title, "{s}   {f}", .{ OwnerName(owner), Bytes{ .mBytes = @intCast(gpu.AtlasBytesOf(owner)) } }),
            .Atlas => try SetLine(engine_context, row.Title, "Texture atlas in use   {f} in slots holding a texture   the array {d} of at most {d} layers ({f} of {f})", .{
                Bytes{ .mBytes = @intCast(atlas.UsedBytes) },
                atlas.Layers,
                atlas.MaxLayers,
                Bytes{ .mBytes = @intCast(atlas.Layers * atlas.LayerBytes) },
                Bytes{ .mBytes = @intCast(atlas.MaxLayers * atlas.LayerBytes) },
            }),
            .AtlasBin => |class_ind| {
                const class = atlas.Classes[class_ind];
                try SetLine(engine_context, row.Title, "Up to {d} px   {f} in {d} slots   {d} free in {d} pages of 8 x 8", .{ class.MaxSize, Bytes{ .mBytes = @intCast(class.Used * class.SlotBytes) }, class.Used, class.Capacity - class.Used, class.Pages });
            },
        }
    }
}

/// Everything at the top, open, with what the engine made under it, by owner and then by group, and what it didn't
fn BuildVideoRows(self: *ProfilerPanel, engine_context: *EngineContext) !void {
    const gpu = &engine_context.mGPUAllocator;
    if (self.mVideoTree) |tree| try Widgets.Remove(engine_context, tree, &.{});
    self.mVideoRows.clearRetainingCapacity();
    const tree = try Widgets.Tree(engine_context, .{ .Entity = self.mVideoContent });
    self.mVideoTree = tree;
    self.mVideoGroups = gpu.mGroups.items.len;
    self.mVideoAtlasOwners = AtlasOwners(gpu);

    const all = try self.AddVideoRow(engine_context, tree, .All, false);
    const ours = try self.AddVideoRow(engine_context, all, .Ours, false);
    for (0..GPUAllocator.OWNER_COUNT) |owner_ind| {
        const owner: GPUAllocator.Owner = @intCast(owner_ind);
        var owner_row: ?Entity = null;
        for (gpu.mGroups.items, 0..) |group, group_ind| {
            if (group.Owner != owner) continue;
            if (owner_row == null) owner_row = try self.AddVideoRow(engine_context, ours, .{ .Owner = owner }, false);
            _ = try self.AddVideoRow(engine_context, owner_row.?, .{ .Group = @intCast(group_ind) }, true);
        }
    }
    _ = try self.AddVideoRow(engine_context, all, .Rest, true);

    //the atlas's use by size class, then by each owner that has slots in it. Which texture is where is the Asset Handles
    //panel's
    const atlas = try self.AddVideoRow(engine_context, tree, .Atlas, false);
    for (0..@typeInfo(@FieldType(TextureManager.Usage, "Classes")).array.len) |class_ind| {
        _ = try self.AddVideoRow(engine_context, atlas, .{ .AtlasBin = @intCast(class_ind) }, true);
    }
    for (0..GPUAllocator.OWNER_COUNT) |owner_ind| {
        if (self.mVideoAtlasOwners & (@as(u32, 1) << @intCast(owner_ind)) == 0) continue;
        _ = try self.AddVideoRow(engine_context, atlas, .{ .AtlasOwner = @intCast(owner_ind) }, true);
    }
}

/// The owners with slots in the texture atlas, a bit each
fn AtlasOwners(gpu: *const GPUAllocator) u32 {
    var owners: u32 = 0;
    for (0..GPUAllocator.OWNER_COUNT) |owner_ind| {
        if (gpu.AtlasBytesOf(@intCast(owner_ind)) > 0) owners |= @as(u32, 1) << @intCast(owner_ind);
    }
    return owners;
}

/// A row of the video memory tree under `parent`, open. Returns where the rows under it go
fn AddVideoRow(self: *ProfilerPanel, engine_context: *EngineContext, parent: Entity, of: VideoRowOf, leaf: bool) !Entity {
    const fold = try Widgets.TreeNode(engine_context, .{ .Entity = parent }, "", .{
        .Open = true,
        .Leaf = leaf,
        .StockScripts = self.mOptions.StockScripts,
    });
    try self.mVideoRows.append(engine_context.ProgramKeep(), .{ .Of = of, .Title = UIManager.LabelOf(fold.Header).? });
    return fold.Content orelse fold.Node;
}

fn OwnerName(owner: GPUAllocator.Owner) []const u8 {
    if (owner == GPUAllocator.ENGINE) return "Engine (shared)";
    return EngineContext.WorldName(owner);
}

/// Each world that ran anything, and its time a pass on average
fn SetWorlds(self: *ProfilerPanel, engine_context: *EngineContext, profiler: *const Profiler) !void {
    var line: std.Io.Writer.Allocating = .init(engine_context.ProgramScratch());
    try line.writer.writeAll("Each world, a pass on average:");
    var any = false;
    for (1..EngineContext.WORLD_NAMES.len + 1) |tag| {
        const world: Profiler.World = @intCast(tag);
        if (!RanOn(profiler, world)) continue;
        try line.writer.print("{s} {s} {f}", .{ if (any) "," else "", EngineContext.WorldName(world), Profiler.Time{ .mDuration = profiler.WorldAverage(world) } });
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
    return try std.fmt.allocPrint(engine_context.ProgramScratch(), "[{s}] {s}", .{ EngineContext.WorldName(profiler.GetNode(node).mWorld), profiler.Name(node) });
}

/// The row of each node met since the last refresh, under its parent's row. Nodes come after their parents, so the
/// parent's row is always there already. The top ones start open, the rest folded
fn AddRows(self: *ProfilerPanel, engine_context: *EngineContext, profiler: *const Profiler) !void {
    const keep_allocator = engine_context.ProgramKeep();
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
    const shown = try engine_context.ProgramScratch().alloc(bool, rows.len);
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
        try SetLine(engine_context, row.Title, "{s}   {f} / {f} / {f}   own {f}   x{d:.1}", .{
            try Title(engine_context, profiler, node),
            Profiler.Time{ .mDuration = summary.Avg },
            Profiler.Time{ .mDuration = summary.P99 },
            Profiler.Time{ .mDuration = summary.Max },
            Profiler.Time{ .mDuration = own },
            summary.Calls,
        });
    }
}

fn IsFolded(row: Row) bool {
    const content = row.Node.Content orelse return true;
    const item = content.GetComponent(LayoutItemComponent) orelse return false;
    return item.mCollapsed;
}


/// A world's folded section in the Rendering section, and its lines
fn WorldSection(engine_context: *EngineContext, content: Entity, title: []const u8, options: Widgets.Options) !WorldLines {
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

/// A world's lines, from the last rendered frame's stats: kept when a pass of the loop skips rendering
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
    try SetLine(engine_context, lines.WorldBVH, "World BVH: overlay {d} items (depth {d}), game {d} items (depth {d}), {d} letter trees ({d} nodes)", .{
        world_bvh.Overlay.Items,
        world_bvh.Overlay.Depth,
        world_bvh.Game.Items,
        world_bvh.Game.Depth,
        world_bvh.LetterTrees,
        world_bvh.LetterNodes,
    });
    try SetLine(engine_context, lines.Entities, "Entities: {d}", .{stats.mECSStats.TotalEntities});
}

/// The Conflicts section, folded to start with
fn BuildConflicts(self: *ProfilerPanel, engine_context: *EngineContext, content: Entity, options: Widgets.Options) !void {
    const section = try Widgets.CollapsingHeader(engine_context, .{ .Entity = content }, "Conflicts (if hooks ran in parallel)", false, options);
    const lines: Widgets.Parent = .{ .Entity = section.Content.? };
    const measure_row = try Widgets.Checkbox(engine_context, lines, "Measure (ticking it starts fresh counts)", options);
    var row_children = measure_row.GetIterator(.Child);
    self.mMeasureBox = row_children.next().?;
    self.mConflictTotal = try Widgets.Label(engine_context, lines, "");
    for (&self.mConflictLines) |*line| line.* = try Widgets.Label(engine_context, lines, "");
}

/// Measuring follows the checkbox, and starts from nothing each time it is ticked
fn SyncMeasuring(self: *ProfilerPanel, engine_context: *EngineContext) !void {
    const conflicts = &engine_context.mTransactions.mConflicts;
    const ticked = self.mMeasureBox.HasComponent(SelectedTag);
    if (ticked == conflicts.mOn) return;
    if (ticked) conflicts.Clear(engine_context.Keep());
    conflicts.mOn = ticked;
}

/// The total and a line for each of the systems with the most hooks: how many of its hooks would conflict, how many
/// would run on their own, and the type most of its conflicts were on
fn SetConflicts(self: *ProfilerPanel, engine_context: *EngineContext, conflicts: *const ConflictReport) !void {
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
    const order = try engine_context.ProgramScratch().alloc(usize, conflicts.mSystems.count());
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

/// Puts a formatted line on a label, if it doesn't say that already
fn SetLine(engine_context: *EngineContext, label: Entity, comptime format: []const u8, args: anytype) !void {
    try WidgetActions.SetText(engine_context, label, try std.fmt.allocPrint(label.mManager.Scratch(), format, args));
}
