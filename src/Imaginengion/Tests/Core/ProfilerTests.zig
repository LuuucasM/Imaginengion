//! The engine's profiler (Core/Profiler.zig): the tree of zones it builds from where each was called, what it keeps of
//! each pass of the loop, and the numbers the Profiler panel shows. Each test measures into a profiler of its own, not
//! the engine's. Run with `zig build test-engine`.
const std = @import("std");

const Profiler = @import("../../Core/Profiler.zig");
const CircularHistory = @import("../../Core/CircularHistory.zig").CircularHistory;
const EngineContext = @import("../../Core/EngineContext.zig");
const WorldManager = @import("../../Core/WorldManager.zig");

fn Started() !*Profiler {
    const profiler = try std.testing.allocator.create(Profiler);
    profiler.* = .{};
    try profiler.Start(std.testing.allocator, std.testing.io);
    return profiler;
}

fn Done(profiler: *Profiler) void {
    profiler.Stop();
    std.testing.allocator.destroy(profiler);
}

fn Zone(profiler: *Profiler, site: *Profiler.Site) !void {
    try std.testing.expect(profiler.Begin(site));
}

fn ChildNames(profiler: *const Profiler, node: Profiler.NodeIndex, names: *[8][]const u8) [][]const u8 {
    var count: usize = 0;
    var children = profiler.Children(node);
    while (children.next()) |child| : (count += 1) names[count] = profiler.Name(child);
    return names[0..count];
}

test "a zone is a node under the zone it was called from, and the same zone called from elsewhere is another node" {
    const profiler = try Started();
    defer Done(profiler);
    var a: Profiler.Site = .{ .mName = "A" };
    var b: Profiler.Site = .{ .mName = "B" };
    var c: Profiler.Site = .{ .mName = "C" };

    //A { B } A { C } B
    try Zone(profiler, &a);
    try Zone(profiler, &b);
    profiler.End();
    profiler.End();
    try Zone(profiler, &a);
    try Zone(profiler, &c);
    profiler.End();
    profiler.End();
    try Zone(profiler, &b);
    profiler.End();

    var names: [8][]const u8 = undefined;
    const top = ChildNames(profiler, Profiler.ROOT, &names);
    try std.testing.expectEqual(@as(usize, 2), top.len);
    try std.testing.expectEqualStrings("A", top[0]);
    try std.testing.expectEqualStrings("B", top[1]);

    var top_nodes = profiler.Children(Profiler.ROOT);
    const a_node = top_nodes.next().?;
    const under_a = ChildNames(profiler, a_node, &names);
    try std.testing.expectEqual(@as(usize, 2), under_a.len);
    try std.testing.expectEqualStrings("B", under_a[0]);
    try std.testing.expectEqualStrings("C", under_a[1]);
    //the root, A, B in A, C in A, B at the top
    try std.testing.expectEqual(@as(Profiler.NodeIndex, 5), profiler.NodeCount());
    try std.testing.expectEqual(@as(u32, 2), profiler.GetNode(a_node).mCalls);
}

test "a zone inside itself is measured as the outer one" {
    const profiler = try Started();
    defer Done(profiler);
    var a: Profiler.Site = .{ .mName = "A" };

    try Zone(profiler, &a);
    try Zone(profiler, &a);
    try Zone(profiler, &a);
    profiler.End();
    profiler.End();
    profiler.End();

    try std.testing.expectEqual(@as(Profiler.NodeIndex, 2), profiler.NodeCount());
    try std.testing.expectEqual(@as(u32, 3), profiler.GetNode(1).mCalls);
    try std.testing.expectEqual(@as(u8, 0), profiler.mDepth);
}

test "the end of a pass of the loop keeps each node's pass and starts the next from nothing" {
    const profiler = try Started();
    defer Done(profiler);
    var a: Profiler.Site = .{ .mName = "A" };
    var b: Profiler.Site = .{ .mName = "B" };

    try Zone(profiler, &a);
    profiler.End();
    try Zone(profiler, &a);
    profiler.End();
    profiler.EndLoop();
    //B only runs the second pass
    try Zone(profiler, &b);
    profiler.End();
    profiler.EndLoop();

    const a_history = profiler.History(1);
    try std.testing.expectEqual(@as(usize, 2), a_history.Calls.count);
    try std.testing.expectEqual(@as(u16, 0), a_history.Calls.latest());
    try std.testing.expectEqual(@as(u32, 0), profiler.GetNode(1).mCalls);
    try std.testing.expectEqual(@as(usize, 1), profiler.History(2).Calls.count);
    try std.testing.expectEqual(@as(u16, 1), profiler.History(2).Calls.latest());
    try std.testing.expectEqual(@as(usize, 2), profiler.LoopsKept());
}

test "a zone still open at the end of a pass stays open into the next" {
    const profiler = try Started();
    defer Done(profiler);
    var a: Profiler.Site = .{ .mName = "A" };

    try Zone(profiler, &a);
    profiler.EndLoop();
    try std.testing.expectEqual(@as(u8, 1), profiler.mDepth);
    profiler.End();
    profiler.EndLoop();
    try std.testing.expectEqual(@as(u16, 1), profiler.History(1).Calls.latest());
}

test "nothing is measured before Start, after Stop, or on another thread" {
    var profiler: Profiler = .{};
    var a: Profiler.Site = .{ .mName = "A" };
    try std.testing.expect(!profiler.Begin(&a));
    profiler.End();
    profiler.EndLoop();

    try profiler.Start(std.testing.allocator, std.testing.io);
    const Other = struct {
        fn Run(measured: *Profiler, site: *Profiler.Site, began: *bool) void {
            began.* = measured.Begin(site);
        }
    };
    var began = true;
    const thread = try std.Thread.spawn(.{}, Other.Run, .{ &profiler, &a, &began });
    thread.join();
    try std.testing.expect(!began);
    try std.testing.expectEqual(@as(Profiler.NodeIndex, 1), profiler.NodeCount());

    profiler.Stop();
    try std.testing.expect(!profiler.Begin(&a));
}

test "zones past the deepest kept are left out, and their ends still match" {
    const profiler = try Started();
    defer Done(profiler);
    var sites: [Profiler.MAX_DEPTH + 4]Profiler.Site = undefined;
    for (&sites) |*site| site.* = .{ .mName = "Deep" };

    for (&sites) |*site| try Zone(profiler, site);
    for (sites) |_| profiler.End();

    try std.testing.expectEqual(@as(Profiler.NodeIndex, Profiler.MAX_DEPTH + 1), profiler.NodeCount());
    try std.testing.expectEqual(@as(u8, 0), profiler.mDepth);
    try std.testing.expectEqual(@as(u32, 0), profiler.mTooDeep);
}

test "with no room for more nodes a new zone is measured as the zone it is inside" {
    const profiler = try Started();
    defer Done(profiler);
    const sites = try std.testing.allocator.alloc(Profiler.Site, Profiler.MAX_NODES + 10);
    defer std.testing.allocator.free(sites);
    for (sites) |*site| site.* = .{ .mName = "Many" };
    var outer: Profiler.Site = .{ .mName = "Outer" };

    try Zone(profiler, &outer);
    for (sites) |*site| {
        try Zone(profiler, site);
        profiler.End();
    }
    profiler.End();
    profiler.EndLoop();

    try std.testing.expectEqual(@as(Profiler.NodeIndex, Profiler.MAX_NODES), profiler.NodeCount());
    //the root and Outer leave room for MAX_NODES - 2 of them; the rest are counted as calls of Outer, with its own
    const without_room = sites.len - (Profiler.MAX_NODES - 2);
    try std.testing.expectEqual(@as(u16, @intCast(1 + without_room)), profiler.History(1).Calls.latest());
}

test "a summary is the average, the 99th percentile and the worst pass, and calls a pass" {
    var times: [1000]u32 = undefined;
    var calls: [1000]u16 = undefined;
    for (&times, &calls, 0..) |*time, *count, i| {
        //in no particular order
        time.* = @intCast((i * 7919) % 1000 + 1);
        count.* = if (i % 2 == 0) 1 else 3;
    }
    const summary = Profiler.SummarizeHistory(&times, &calls);
    try std.testing.expectEqual(@as(i96, 500), summary.Avg.toNanoseconds());
    try std.testing.expectEqual(@as(i96, 1000), summary.Max.toNanoseconds());
    //1000 / 100 + 1 = the 11th largest: 10 passes took longer
    try std.testing.expectEqual(@as(i96, 990), summary.P99.toNanoseconds());
    try std.testing.expectEqual(@as(f32, 2), summary.Calls);
    try std.testing.expectEqual(@as(usize, 1000), summary.Loops);

    const empty = Profiler.SummarizeHistory(&.{}, &.{});
    try std.testing.expectEqual(@as(usize, 0), empty.Loops);
}

test "a circular history keeps the last items, and the latest" {
    var history: CircularHistory(u32, 4) = .empty;
    for (1..7) |i| history.append(@intCast(i));
    try std.testing.expectEqual(@as(usize, 4), history.items().len);
    var total: u32 = 0;
    for (history.items()) |item| total += item;
    try std.testing.expectEqual(@as(u32, 3 + 4 + 5 + 6), total);
    try std.testing.expectEqual(@as(u32, 6), history.latest());
}

test "the same zone on two worlds is two nodes, what it calls is on its world too, and each world adds up its own time" {
    const profiler = try Started();
    defer Done(profiler);
    var loop: Profiler.Site = .{ .mName = "Loop" };
    var run: Profiler.Site = .{ .mName = "Run" };
    var inner: Profiler.Site = .{ .mName = "Inner" };
    const game: Profiler.World = 1;
    const playing: Profiler.World = 2;

    //Loop { [game] Run { Inner }  [playing] Run { Inner } }
    try Zone(profiler, &loop);
    for ([_]Profiler.World{ game, playing }) |world| {
        const outer = profiler.EnterWorld(world);
        try Zone(profiler, &run);
        try Zone(profiler, &inner);
        profiler.End();
        profiler.End();
        profiler.LeaveWorld(outer);
    }
    profiler.End();
    profiler.EndLoop();

    //Loop is on no world, then a Run and an Inner for each world
    try std.testing.expectEqual(@as(Profiler.NodeIndex, 6), profiler.NodeCount());
    const loop_node: Profiler.NodeIndex = 1;
    try std.testing.expectEqual(Profiler.NO_WORLD, profiler.GetNode(loop_node).mWorld);
    var names: [8][]const u8 = undefined;
    try std.testing.expectEqual(@as(usize, 2), ChildNames(profiler, loop_node, &names).len);
    var runs = profiler.Children(loop_node);
    const game_run = runs.next().?;
    const playing_run = runs.next().?;
    try std.testing.expectEqual(game, profiler.GetNode(game_run).mWorld);
    try std.testing.expectEqual(playing, profiler.GetNode(playing_run).mWorld);
    try std.testing.expect(profiler.StartsWorld(game_run));
    //what it calls is on its world, and doesn't start it again
    var game_children = profiler.Children(game_run);
    const game_inner = game_children.next().?;
    try std.testing.expectEqual(game, profiler.GetNode(game_inner).mWorld);
    try std.testing.expect(!profiler.StartsWorld(game_inner));

    //a world's time is its top nodes' time
    profiler.History(game_run).Times.append(5000);
    profiler.History(game_inner).Times.append(3000);
    try std.testing.expectEqual(profiler.Average(game_run).toNanoseconds(), profiler.WorldAverage(game).toNanoseconds());
    //leaving a world goes back to the one outside it
    try std.testing.expectEqual(Profiler.NO_WORLD, profiler.mWorld);
}

test "a system handed a world is measured on that world, and the world is left when it ends" {
    const engine_context = try std.heap.page_allocator.create(EngineContext);
    defer std.heap.page_allocator.destroy(engine_context);
    engine_context.* = .{};
    try Profiler.gMain.Start(std.testing.allocator, std.testing.io);
    defer Profiler.gMain.Stop();

    const WorldSystem = struct {
        pub const Name = "ProfilerTests::WorldSystem";
        pub fn Run(_: *EngineContext, _: *WorldManager) void {}
    };
    try engine_context.mSystems.RunSystem(WorldSystem, engine_context, .{&engine_context.mSimulateWorld});

    var found = false;
    for (1..Profiler.gMain.NodeCount()) |node_ind| {
        const node: Profiler.NodeIndex = @intCast(node_ind);
        if (!std.mem.eql(u8, Profiler.gMain.Name(node), WorldSystem.Name)) continue;
        found = true;
        try std.testing.expectEqual(engine_context.WorldTag(&engine_context.mSimulateWorld), Profiler.gMain.GetNode(node).mWorld);
        try std.testing.expectEqualStrings("Playing", EngineContext.WorldName(Profiler.gMain.GetNode(node).mWorld));
    }
    try std.testing.expect(found);
    try std.testing.expectEqual(Profiler.NO_WORLD, Profiler.gMain.mWorld);
}
