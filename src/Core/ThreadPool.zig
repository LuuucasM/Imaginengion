const std = @import("std");
const builtin = @import("builtin");
const Pool = @This();

var ThreadPool: *Pool = undefined;

mutex: std.Thread.Mutex = .{},
cond: std.Thread.Condition = .{},
_WaitCond: std.Thread.Condition = .{},
run_queue: RunQueue = .{},
is_running: bool = true,
_PoolArena: std.heap.ArenaAllocator,
allocator: std.mem.Allocator,
threads: []std.Thread,
_WorkingCount: u8 = 0,

const RunQueue = std.SinglyLinkedList(Runnable);
const Runnable = struct {
    runFn: RunProto,
};

const RunProto = *const fn (*Runnable) void;

pub const Options = struct {
    allocator: std.mem.Allocator,
    n_jobs: ?u32 = null,
};

pub fn init(EngineAllocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    ThreadPool = try EngineAllocator.create(Pool);
    ThreadPool.* = .{
        ._PoolArena = arena,
        .allocator = allocator,
        .threads = &[_]std.Thread{},
    };

    if (builtin.single_threaded) {
        return;
    }

    const thread_count = @max(1, std.Thread.getCpuCount() catch 1);

    // kill and join any threads we spawned and free memory on error.
    ThreadPool.threads = try allocator.alloc(std.Thread, thread_count);
    var spawned: usize = 0;
    errdefer ThreadPool.join(spawned);

    for (ThreadPool.threads) |*thread| {
        thread.* = try std.Thread.spawn(.{}, worker, .{ThreadPool});
        spawned += 1;
    }
}

pub fn deinit() void {
    ThreadPool.join(ThreadPool.threads.len); // kill and join all threads.
    ThreadPool.* = undefined;
}

fn join(pool: *Pool, spawned: usize) void {
    if (builtin.single_threaded) {
        return;
    }

    {
        pool.mutex.lock();
        defer pool.mutex.unlock();

        // ensure future worker threads exit the dequeue loop
        pool.is_running = false;
    }

    // wake up any sleeping threads (this can be done outside the mutex)
    // then wait for all the threads we know are spawned to complete.
    pool.cond.broadcast();
    for (pool.threads[0..spawned]) |thread| {
        thread.join();
    }

    pool.allocator.free(pool.threads);
}

pub fn spawn(comptime func: anytype, args: anytype) !void {
    if (builtin.single_threaded) {
        @call(.auto, func, args);
        return;
    }

    const Args = @TypeOf(args);
    const Closure = struct {
        arguments: Args,
        pool: *Pool,
        run_node: RunQueue.Node = .{ .data = .{ .runFn = runFn } },

        fn runFn(runnable: *Runnable) void {
            const run_node: *RunQueue.Node = @fieldParentPtr("data", runnable);
            const closure: *@This() = @fieldParentPtr("run_node", run_node);
            @call(.auto, func, closure.arguments);
        }
    };

    {
        ThreadPool.mutex.lock();
        defer ThreadPool.mutex.unlock();

        const closure = try ThreadPool.allocator.create(Closure);
        closure.* = .{
            .arguments = args,
            .pool = ThreadPool,
        };

        ThreadPool.run_queue.prepend(&closure.run_node);
    }

    // Notify waiting threads outside the lock to try and keep the critical section small.
    ThreadPool.cond.signal();
}

fn worker(pool: *Pool) void {
    pool.mutex.lock();
    defer pool.mutex.unlock();

    while (true) {
        while (pool.run_queue.popFirst()) |run_node| {
            ThreadPool._WorkingCount += 1;
            // Temporarily unlock the mutex in order to execute the run_node
            pool.mutex.unlock();

            const runFn = run_node.data.runFn;
            runFn(&run_node.data);

            //deincrement working count
            pool.mutex.lock();
            ThreadPool._WorkingCount -= 1;
            pool._WaitCond.signal();
        }

        // Stop executing instead of waiting if the thread pool is no longer running.
        if (pool.is_running) {
            pool.cond.wait(&pool.mutex);
        } else {
            break;
        }
    }
}

pub fn WaitTilDone() void {
    ThreadPool.mutex.lock();
    defer ThreadPool.mutex.unlock();
    while (ThreadPool._WorkingCount != 0) {
        ThreadPool._WaitCond.wait(ThreadPool.mutex);
    }
}
