//! The engine's Io for jobs (EngineContext.Io, Core/JobGroup.zig): a group's tasks are queued by async and run by
//! await, on the pool's workers and the waiting thread together. Run with `zig build test-engine`.
const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig");
const Allocators = @import("../../Core/Allocators.zig");

/// A context with a job pool of `workers` threads (none for 0), and the pool to tear down
const TestJobs = struct {
    mEngineContext: *EngineContext,
    mThreads: ?*std.Io.Threaded = null,

    fn Init(workers: usize) !TestJobs {
        const engine_context = try std.heap.page_allocator.create(EngineContext);
        engine_context.* = .{};
        var self: TestJobs = .{ .mEngineContext = engine_context };
        if (workers > 0) {
            const threads = try std.heap.page_allocator.create(std.Io.Threaded);
            threads.* = std.Io.Threaded.init(std.heap.page_allocator, .{ .async_limit = .limited(workers), .concurrent_limit = .nothing });
            self.mThreads = threads;
            engine_context.mJobPool = .{ .mIo = threads.io(), .mWorkers = workers };
            engine_context._Internal.ThreadFrameArenas.mMainThread = std.Thread.getCurrentId();
        }
        return self;
    }

    fn Deinit(self: TestJobs) !void {
        if (self.mThreads) |threads| {
            threads.deinit();
            std.heap.page_allocator.destroy(threads);
        }
        self.mEngineContext._Internal.ThreadFrameArenas.Deinit();
        const leak_check = self.mEngineContext._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(self.mEngineContext);
        try std.testing.expect(leak_check == .ok);
    }
};

fn Doubles(results: []u64, index: usize) void {
    results[index] = index * 2;
}

test "a job group's tasks are queued by async, and all run by await" {
    for ([_]usize{ 0, 4 }) |workers| {
        const jobs = try TestJobs.Init(workers);
        defer jobs.Deinit() catch unreachable;
        const io = jobs.mEngineContext.Io();
        var results: [100]u64 = @splat(std.math.maxInt(u64));

        var group: std.Io.Group = .init;
        for (0..results.len) |index| group.async(io, Doubles, .{ &results, index });
        //nothing has run yet
        for (results) |result| try std.testing.expectEqual(std.math.maxInt(u64), result);

        try group.await(io);
        for (results, 0..) |result, index| try std.testing.expectEqual(index * 2, result);
    }
}

/// How many Meets tasks have started, and the thread each ran on
var gArrived: std.atomic.Value(u32) = .init(0);

fn Meets(thread: *std.Thread.Id, met: *bool) void {
    thread.* = std.Thread.getCurrentId();
    _ = gArrived.fetchAdd(1, .acq_rel);
    var spins: u64 = 0;
    while (gArrived.load(.acquire) < 2 and spins < 4_000_000_000) : (spins += 1) std.atomic.spinLoopHint();
    met.* = gArrived.load(.acquire) >= 2;
}

test "the thread waiting on a job group works through it too, side by side with the pool" {
    const jobs = try TestJobs.Init(1);
    defer jobs.Deinit() catch unreachable;
    const io = jobs.mEngineContext.Io();
    gArrived = .init(0);
    var threads: [2]std.Thread.Id = undefined;
    var met = [_]bool{ false, false };

    var group: std.Io.Group = .init;
    for (0..2) |index| group.async(io, Meets, .{ &threads[index], &met[index] });
    try group.await(io);

    //one worker and this thread, each running one at the same time
    try std.testing.expect(met[0] and met[1]);
    try std.testing.expect(threads[0] != threads[1]);
    const this_thread = std.Thread.getCurrentId();
    try std.testing.expect(threads[0] == this_thread or threads[1] == this_thread);
}

/// Meets, then takes some frame memory and writes down which arena it came from
fn MeetsAndAllocates(engine_context: *EngineContext, thread: *std.Thread.Id, met: *bool, arena: **std.heap.ArenaAllocator) void {
    Meets(thread, met);
    _ = engine_context.FrameAllocator().alloc(u8, 4096) catch unreachable;
    arena.* = Allocators.FrameArenaOf(engine_context);
}

test "a task on a worker thread takes frame memory from that thread's own arena, the waiting thread from the engine's" {
    const jobs = try TestJobs.Init(1);
    defer jobs.Deinit() catch unreachable;
    const engine_context = jobs.mEngineContext;
    const io = engine_context.Io();
    gArrived = .init(0);
    var threads: [2]std.Thread.Id = undefined;
    var met = [_]bool{ false, false };
    var arenas: [2]*std.heap.ArenaAllocator = undefined;

    var group: std.Io.Group = .init;
    for (0..2) |index| group.async(io, MeetsAndAllocates, .{ engine_context, &threads[index], &met[index], &arenas[index] });
    try group.await(io);

    try std.testing.expect(met[0] and met[1]);
    const this_thread = std.Thread.getCurrentId();
    for (threads, arenas) |thread, arena| {
        if (thread == this_thread) {
            try std.testing.expect(arena == &engine_context._Internal.FrameArena);
        } else {
            try std.testing.expect(arena != &engine_context._Internal.FrameArena);
            try std.testing.expect(arena.queryCapacity() >= 4096);
        }
    }
    //emptied with the engine's at the end of the frame, keeping the memory
    engine_context._Internal.ThreadFrameArenas.Reset();
}
