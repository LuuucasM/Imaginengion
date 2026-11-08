const std = @import("std");
const EngineContext = @import("EngineContext.zig");
const AllocType = EngineContext.AllocType;
const Tracy = @import("Tracy.zig");

/// The frame arenas of the threads other than the main one: the engine's frame arena (EngineContext._Internal.FrameArena)
/// isn't safe to share between threads, so a thread of the job pool running a task gets one of its own the first time it
/// takes frame memory, kept for as long as the thread is, and emptied with the main one at the end of every frame
pub const ThreadFrameArenas = struct {
    /// The main thread, which uses the engine's frame arena. Null (before EngineContext.Init) for every thread using it
    mMainThread: ?std.Thread.Id = null,
    /// Every thread's arena made so far, newest first. Added to by the threads themselves, so atomically
    mHead: std.atomic.Value(?*ThreadArena) = .init(null),

    /// Empties every thread's arena, keeping its memory: at the end of the frame, while no task is running
    pub fn Reset(self: *ThreadFrameArenas) void {
        var node = self.mHead.load(.acquire);
        while (node) |arena| : (node = arena.mNext) _ = arena.mArena.reset(.retain_capacity);
    }

    /// Lets go of every thread's arena: once the pool's threads are gone
    pub fn Deinit(self: *ThreadFrameArenas) void {
        var node = self.mHead.swap(null, .acq_rel);
        while (node) |arena| {
            node = arena.mNext;
            arena.mArena.deinit();
            std.heap.page_allocator.destroy(arena);
        }
    }
};

/// One thread's frame arena (ThreadFrameArenas)
const ThreadArena = struct {
    mArena: std.heap.ArenaAllocator,
    mNext: ?*ThreadArena,
};

/// The calling thread's own frame arena, and whose list it is in: read only by Backing, which is always the engine's
/// copy of this code (the vtable is filled in by the engine), so only the engine's threadlocal is ever used
threadlocal var tArena: ?*ThreadArena = null;
threadlocal var tArenaOwner: ?*ThreadFrameArenas = null;

/// The frame arena the calling thread takes frame memory from: the engine's on the main thread, the thread's own on any
/// other (made the first time). With no memory for a thread's own, the engine's, as before threads
pub fn FrameArenaOf(engine_context: *EngineContext) *std.heap.ArenaAllocator {
    const arenas = &engine_context._Internal.ThreadFrameArenas;
    const main_thread = arenas.mMainThread orelse return &engine_context._Internal.FrameArena;
    if (std.Thread.getCurrentId() == main_thread) return &engine_context._Internal.FrameArena;
    if (tArenaOwner == arenas) {
        if (tArena) |own| return &own.mArena;
    }
    const made = std.heap.page_allocator.create(ThreadArena) catch return &engine_context._Internal.FrameArena;
    made.* = .{ .mArena = std.heap.ArenaAllocator.init(std.heap.page_allocator), .mNext = arenas.mHead.load(.acquire) };
    while (arenas.mHead.cmpxchgWeak(made.mNext, made, .acq_rel, .acquire)) |head| made.mNext = head;
    tArena = made;
    tArenaOwner = arenas;
    return &made.mArena;
}

/// Every engine and frame allocation passes through here, which is what lets Tracy see all of them.
/// Each allocator reports to its own named pool so the two show up separately in Tracy's memory window.
pub inline fn MakeAllocatorVTable(comptime alloc_type: AllocType) type {
    const pool: Tracy.MemoryPool = switch (alloc_type) {
        .Engine => .Engine,
        .Frame => .Frame,
    };
    const fns = struct {
        fn Backing(context: *anyopaque) std.mem.Allocator {
            const engine_context: *EngineContext = @ptrCast(@alignCast(context));
            return switch (alloc_type) {
                .Engine => engine_context._Internal.EngineGPA.allocator(),
                //a thread of the job pool has an arena of its own: the engine's isn't safe to share
                .Frame => FrameArenaOf(engine_context).allocator(),
            };
        }
        fn alloc(context: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
            const allocator = Backing(context);
            const result = allocator.vtable.alloc(allocator.ptr, len, alignment, ret_addr);
            if (result) |ptr| Tracy.MemAlloc(pool, ptr, len);
            return result;
        }
        // resize and remap report the old block freed before the call and then whichever block is live
        // after it, so Tracy never sees an address handed out while it still thinks it is in use,
        // including when the call fails and the original block simply stays
        fn resize(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, return_address: usize) bool {
            const allocator = Backing(context);
            Tracy.MemFree(pool, memory.ptr);
            const resized = allocator.vtable.resize(allocator.ptr, memory, alignment, new_len, return_address);
            Tracy.MemAlloc(pool, memory.ptr, if (resized) new_len else memory.len);
            return resized;
        }
        fn remap(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, return_address: usize) ?[*]u8 {
            const allocator = Backing(context);
            Tracy.MemFree(pool, memory.ptr);
            const result = allocator.vtable.remap(allocator.ptr, memory, alignment, new_len, return_address);
            if (result) |ptr| {
                Tracy.MemAlloc(pool, ptr, new_len);
            } else {
                Tracy.MemAlloc(pool, memory.ptr, memory.len);
            }
            return result;
        }
        fn free(context: *anyopaque, old_memory: []u8, alignment: std.mem.Alignment, return_address: usize) void {
            const allocator = Backing(context);
            Tracy.MemFree(pool, old_memory.ptr);
            allocator.vtable.free(allocator.ptr, old_memory, alignment, return_address);
        }
    };
    return struct {
        pub const vtable: std.mem.Allocator.VTable = .{
            .alloc = fns.alloc,
            .resize = fns.resize,
            .remap = fns.remap,
            .free = fns.free,
        };
    };
}
