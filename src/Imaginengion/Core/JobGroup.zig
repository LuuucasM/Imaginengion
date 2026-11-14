//! The tasks of one std.Io.Group on one of the engine's Ios (EngineContext.Io for jobs, EngineContext.AriaIo for
//! transactions): Group.async only adds a task here, running nothing, and Group.await runs them all. So the whole group
//! is queued before any of it starts, and await is where the main thread works through it alongside the pool's workers
//! (ParallelFor), rather than waiting. The group's token holds it between the two.
const JobGroup = @This();

const std = @import("std");
const EngineContext = @import("EngineContext.zig");
const Tracy = @import("Tracy.zig");

/// Where the tasks' copied arguments live
mArena: std.heap.ArenaAllocator,
/// The tasks, in the order they were added
mTasks: std.ArrayList(Task) = .empty,

/// One task: Group.async's function and a copy of its arguments
pub const Task = struct {
    mContext: *const anyopaque,
    mStart: *const fn (context: *const anyopaque) void,

    pub fn Run(self: Task) void {
        self.mStart(self.mContext);
    }
};

/// The thread pool the engine's jobs run on, and how many workers it has besides the thread waiting on it. No Io runs
/// everything on the calling thread (tests that don't ask for a pool)
pub const Pool = struct {
    mIo: ?std.Io = null,
    mWorkers: usize = 0,
};

/// Adds a task to `group`, making the group's JobGroup the first time: a vtable groupAsync. The arguments are copied.
/// With no memory to queue it in, the task runs right away instead
pub fn Add(keep_allocator: std.mem.Allocator, group: *std.Io.Group, context: []const u8, context_alignment: std.mem.Alignment, start: *const fn (context: *const anyopaque) void) void {
    _AddOrFail(keep_allocator, group, context, context_alignment, start) catch start(context.ptr);
}

fn _AddOrFail(keep_allocator: std.mem.Allocator, group: *std.Io.Group, context: []const u8, context_alignment: std.mem.Alignment, start: *const fn (context: *const anyopaque) void) !void {
    const self = Of(group) orelse blk: {
        const made = try keep_allocator.create(JobGroup);
        made.* = .{ .mArena = std.heap.ArenaAllocator.init(keep_allocator) };
        group.token.store(made, .release);
        break :blk made;
    };
    const copy = self.mArena.allocator().rawAlloc(context.len, context_alignment, @returnAddress()) orelse return error.OutOfMemory;
    @memcpy(copy[0..context.len], context);
    try self.mTasks.append(self.mArena.allocator(), .{ .mContext = copy, .mStart = start });
}

/// The JobGroup `group` holds, null for one nothing was added to
pub fn Of(group: *std.Io.Group) ?*JobGroup {
    const token = group.token.load(.acquire) orelse return null;
    return @ptrCast(@alignCast(token));
}

/// Lets go of the tasks, and leaves `group` empty, as Group.await and Group.cancel have to
pub fn Free(self: *JobGroup, keep_allocator: std.mem.Allocator, group: *std.Io.Group) void {
    self.mArena.deinit();
    keep_allocator.destroy(self);
    group.token.store(null, .release);
}

/// Runs every task, on the pool's workers and the calling thread together: a vtable groupAwait for jobs
pub fn RunAll(self: *JobGroup, pool: Pool) void {
    const zone = Tracy.ZoneInit("JobGroup::RunAll", @src());
    defer zone.Deinit();
    zone.Value(self.mTasks.items.len);
    ParallelFor(pool, self.mTasks.items.len, self.mTasks.items, struct {
        fn Run(tasks: []const Task, index: usize) void {
            tasks[index].Run();
        }
    }.Run);
}

/// Calls run(context, i) once for every i below `count`. One loop per worker of the pool, and one on the calling
/// thread, each taking the next i nobody has started until none is left; then it waits for the workers' loops to end.
/// So the calling thread works as long as there is anything left to start, and each i costs one atomic add. With no
/// pool, or nothing for a worker to do, it all runs on the calling thread
pub fn ParallelFor(pool: Pool, count: usize, context: anytype, comptime run: fn (@TypeOf(context), usize) void) void {
    const Context = @TypeOf(context);
    const Loop = struct {
        fn Drain(loop_context: Context, next: *std.atomic.Value(usize), total: usize) void {
            while (true) {
                const index = next.fetchAdd(1, .monotonic);
                if (index >= total) return;
                run(loop_context, index);
            }
        }
    };

    var next: std.atomic.Value(usize) = .init(0);
    const loops = @min(pool.mWorkers, count -| 1);
    const io = pool.mIo orelse return Loop.Drain(context, &next, count);
    if (loops == 0) return Loop.Drain(context, &next, count);

    var group: std.Io.Group = .init;
    for (0..loops) |_| group.async(io, Loop.Drain, .{ context, &next, count });
    Loop.Drain(context, &next, count);
    group.await(io) catch |err| std.debug.panic("Waiting for a job's workers was {s}", .{@errorName(err)});
}

//----------------the vtable's group calls for jobs (Core/Ios.zig)----------------

pub fn GroupAsync(userdata: ?*anyopaque, group: *std.Io.Group, context: []const u8, context_alignment: std.mem.Alignment, start: *const fn (context: *const anyopaque) void) void {
    const engine_context: *EngineContext = @ptrCast(@alignCast(userdata.?));
    Add(engine_context.Keep(), group, context, context_alignment, start);
}

pub fn GroupAwait(userdata: ?*anyopaque, group: *std.Io.Group, token: *anyopaque) std.Io.Cancelable!void {
    const engine_context: *EngineContext = @ptrCast(@alignCast(userdata.?));
    const self: *JobGroup = @ptrCast(@alignCast(token));
    //inside an open transaction (a refit from a serial hook's cast): its tasks read through it, and it writes down what
    //they read, which isn't safe from several threads, so they all run here
    const pool: Pool = if (engine_context.mTransactions.Current() != null) .{} else engine_context.mJobPool;
    self.RunAll(pool);
    self.Free(engine_context.Keep(), group);
}

/// Nothing has started before await, so canceling only lets go of the tasks
pub fn GroupCancel(userdata: ?*anyopaque, group: *std.Io.Group, token: *anyopaque) void {
    const engine_context: *EngineContext = @ptrCast(@alignCast(userdata.?));
    const self: *JobGroup = @ptrCast(@alignCast(token));
    self.Free(engine_context.Keep(), group);
}
