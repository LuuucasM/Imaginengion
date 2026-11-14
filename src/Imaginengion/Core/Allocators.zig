//! The engine's allocators, each named for what its memory is for (EngineContext.AllocType):
//!   - Keep: lasts until it is freed. Taken from KeepHeap
//!   - Scratch: for the current pass of the loop only, emptied all at once at its end. An arena per thread
//! Each has an owner (Owner): the engine, for what every world shares (UI land, assets, audio, the renderer), or one world,
//! for what is only that world's (WorldAllocators). Every owner takes from the same KeepHeap and scratch arenas, so memory
//! freed through another owner than the one that took it is only counted against the wrong one, never lost. Every
//! allocation passes through MakeAllocatorVTable, the one place to count or limit them.
const std = @import("std");
const builtin = @import("builtin");
const EngineContext = @import("EngineContext.zig");
const AllocType = EngineContext.AllocType;
const Tracy = @import("Tracy.zig");

/// Where Keep's memory comes from. Debug and ReleaseSafe keep their safety checks for memory too: DebugAllocator
/// catches leaks, double frees and use after free, at a cost to speed. ReleaseFast and ReleaseSmall drop them for
/// SmpAllocator, std's fast allocator for many threads. It is one for the whole process, so this holds nothing then
pub const KeepHeap = switch (builtin.mode) {
    .Debug, .ReleaseSafe => struct {
        mDebug: std.heap.DebugAllocator(.{}) = .init,

        pub fn allocator(self: *KeepHeap) std.mem.Allocator {
            return self.mDebug.allocator();
        }

        /// Whether anything taken from it was never freed, each one logged
        pub fn deinit(self: *KeepHeap) std.heap.Check {
            return self.mDebug.deinit();
        }
    },
    .ReleaseFast, .ReleaseSmall => struct {
        pub fn allocator(_: *KeepHeap) std.mem.Allocator {
            return std.heap.smp_allocator;
        }

        /// SmpAllocator keeps no record to check for leaks
        pub fn deinit(_: *KeepHeap) std.heap.Check {
            return .ok;
        }
    },
};

/// The scratch arenas of the threads other than the main one: the engine's scratch arena (EngineContext._Internal.ScratchArena)
/// isn't safe to share between threads, so a thread of the job pool running a task gets one of its own the first time it
/// takes scratch memory, kept for as long as the thread is, and emptied with the main one at the end of every pass of the loop
pub const ThreadScratchArenas = struct {
    /// The main thread, which uses the engine's scratch arena. Null (before EngineContext.Init) for every thread using it
    mMainThread: ?std.Thread.Id = null,
    /// Every thread's arena made so far, newest first. Added to by the threads themselves, so atomically
    mHead: std.atomic.Value(?*ThreadArena) = .init(null),

    /// Empties every thread's arena, keeping its memory: at the end of the frame, while no task is running
    pub fn Reset(self: *ThreadScratchArenas) void {
        var node = self.mHead.load(.acquire);
        while (node) |arena| : (node = arena.mNext) _ = arena.mArena.reset(.retain_capacity);
    }

    /// Lets go of every thread's arena: once the pool's threads are gone
    pub fn Deinit(self: *ThreadScratchArenas) void {
        var node = self.mHead.swap(null, .acq_rel);
        while (node) |arena| {
            node = arena.mNext;
            arena.mArena.deinit();
            std.heap.page_allocator.destroy(arena);
        }
    }
};

/// One thread's scratch arena (ThreadScratchArenas)
const ThreadArena = struct {
    mArena: std.heap.ArenaAllocator,
    mNext: ?*ThreadArena,
};

/// The calling thread's own scratch arena, and whose list it is in: read only by Backing, which is always the engine's
/// copy of this code (the vtable is filled in by the engine), so only the engine's threadlocal is ever used
threadlocal var tArena: ?*ThreadArena = null;
threadlocal var tArenaOwner: ?*ThreadScratchArenas = null;

/// The scratch arena the calling thread takes scratch memory from: the engine's on the main thread, the thread's own on any
/// other (made the first time). With no memory for a thread's own, the engine's, as before threads
pub fn ScratchArenaOf(engine_context: *EngineContext) *std.heap.ArenaAllocator {
    const arenas = &engine_context._Internal.ThreadScratchArenas;
    const main_thread = arenas.mMainThread orelse return &engine_context._Internal.ScratchArena;
    if (std.Thread.getCurrentId() == main_thread) return &engine_context._Internal.ScratchArena;
    if (tArenaOwner == arenas) {
        if (tArena) |own| return &own.mArena;
    }
    const made = std.heap.page_allocator.create(ThreadArena) catch return &engine_context._Internal.ScratchArena;
    made.* = .{ .mArena = std.heap.ArenaAllocator.init(std.heap.page_allocator), .mNext = arenas.mHead.load(.acquire) };
    while (arenas.mHead.cmpxchgWeak(made.mNext, made, .acq_rel, .acquire)) |head| made.mNext = head;
    tArena = made;
    tArenaOwner = arenas;
    return &made.mArena;
}

/// What one owner (the engine, or one world) has taken, counted by MakeAllocatorVTable as it is taken. Atomic, since the
/// job pool's threads take memory too. Signed: memory taken through one owner and freed through another (Allocators.zig)
/// moves bytes from one to the other, so an owner can go below nothing, which shows rather than wrapping around
pub const Counts = struct {
    /// Keep bytes held now, and the most ever held at once
    mKeepBytes: std.atomic.Value(i64) = .init(0),
    mKeepPeak: std.atomic.Value(i64) = .init(0),
    /// Keep allocations held now
    mKeepAllocs: std.atomic.Value(i64) = .init(0),
    /// Scratch bytes taken so far this pass of the loop. Scratch is never freed by hand, so this only goes up until EndPass
    mScratchBytes: std.atomic.Value(i64) = .init(0),
    /// Scratch bytes the last whole pass took, and the most any pass took. Only changed by EndPass, between passes
    mScratchLast: i64 = 0,
    mScratchPeak: i64 = 0,

    /// What it has taken, read all at once
    pub const Snapshot = struct {
        KeepBytes: i64,
        KeepPeak: i64,
        KeepAllocs: i64,
        ScratchLast: i64,
        ScratchPeak: i64,
    };

    pub fn Read(self: *const Counts) Snapshot {
        return .{
            .KeepBytes = self.mKeepBytes.load(.monotonic),
            .KeepPeak = self.mKeepPeak.load(.monotonic),
            .KeepAllocs = self.mKeepAllocs.load(.monotonic),
            .ScratchLast = self.mScratchLast,
            .ScratchPeak = self.mScratchPeak,
        };
    }

    /// The pass of the loop is over: what it took of Scratch becomes the last pass's. Once a pass, while no task runs
    pub fn EndPass(self: *Counts) void {
        self.mScratchLast = self.mScratchBytes.swap(0, .monotonic);
        self.mScratchPeak = @max(self.mScratchPeak, self.mScratchLast);
    }

    fn Took(self: *Counts, comptime alloc_type: AllocType, bytes: usize) void {
        const signed: i64 = @intCast(bytes);
        switch (alloc_type) {
            .Keep => {
                const now = self.mKeepBytes.fetchAdd(signed, .monotonic) + signed;
                _ = self.mKeepPeak.fetchMax(now, .monotonic);
                _ = self.mKeepAllocs.fetchAdd(1, .monotonic);
            },
            .Scratch => _ = self.mScratchBytes.fetchAdd(signed, .monotonic),
        }
    }

    fn Gave(self: *Counts, comptime alloc_type: AllocType, bytes: usize) void {
        switch (alloc_type) {
            .Keep => {
                _ = self.mKeepBytes.fetchSub(@intCast(bytes), .monotonic);
                _ = self.mKeepAllocs.fetchSub(1, .monotonic);
            },
            //an arena keeps what is freed until the end of the pass, which is when the count goes too
            .Scratch => {},
        }
    }

    /// An allocation that grew or shrank in place, or moved
    fn Changed(self: *Counts, comptime alloc_type: AllocType, old_bytes: usize, new_bytes: usize) void {
        const change = @as(i64, @intCast(new_bytes)) - @as(i64, @intCast(old_bytes));
        switch (alloc_type) {
            .Keep => {
                const now = self.mKeepBytes.fetchAdd(change, .monotonic) + change;
                _ = self.mKeepPeak.fetchMax(now, .monotonic);
            },
            .Scratch => if (change > 0) {
                _ = self.mScratchBytes.fetchAdd(change, .monotonic);
            },
        }
    }
};

/// Who an allocation is taken for: what an allocator's context points at
pub const Owner = enum {
    /// the context is the EngineContext itself
    Engine,
    /// the context is a world's WorldAllocators
    World,
};

/// One world's own Keep and Scratch (WorldManager.Keep, WorldManager.Scratch): the engine's heap and scratch arenas,
/// taken through the world so what it takes can be told apart from the engine's and the other worlds'
pub const WorldAllocators = struct {
    /// Set by Init, before anything is taken
    mEngineContext: *EngineContext = undefined,
    /// What the world has taken
    mCounts: Counts = .{},

    // Stored for the same reason EngineContext stores its own (see EngineContext.InternalData): a script DLL reading them
    // through the world runs the engine's allocator code, not its own copy
    mKeepVTable: *const std.mem.Allocator.VTable = &MakeAllocatorVTable(.Keep, .World).vtable,
    mScratchVTable: *const std.mem.Allocator.VTable = &MakeAllocatorVTable(.Scratch, .World).vtable,

    pub fn Init(self: *WorldAllocators, engine_context: *EngineContext) void {
        self.mEngineContext = engine_context;
    }

    pub fn Keep(self: *WorldAllocators) std.mem.Allocator {
        return .{ .ptr = self, .vtable = self.mKeepVTable };
    }

    pub fn Scratch(self: *WorldAllocators) std.mem.Allocator {
        return .{ .ptr = self, .vtable = self.mScratchVTable };
    }
};

/// Every Keep and Scratch allocation passes through here, which is what lets Tracy see all of them.
/// Each allocator reports to its own named pool so the two show up separately in Tracy's memory window.
pub inline fn MakeAllocatorVTable(comptime alloc_type: AllocType, comptime owner: Owner) type {
    const pool: Tracy.MemoryPool = switch (alloc_type) {
        .Keep => .Keep,
        .Scratch => .Scratch,
    };
    const fns = struct {
        fn CountsOf(context: *anyopaque) *Counts {
            return switch (owner) {
                .Engine => &@as(*EngineContext, @ptrCast(@alignCast(context)))._Internal.Counts,
                .World => &@as(*WorldAllocators, @ptrCast(@alignCast(context))).mCounts,
            };
        }
        fn Backing(context: *anyopaque) std.mem.Allocator {
            const engine_context: *EngineContext = switch (owner) {
                .Engine => @ptrCast(@alignCast(context)),
                .World => @as(*WorldAllocators, @ptrCast(@alignCast(context))).mEngineContext,
            };
            return switch (alloc_type) {
                .Keep => engine_context._Internal.KeepHeap.allocator(),
                //a thread of the job pool has an arena of its own: the engine's isn't safe to share
                .Scratch => ScratchArenaOf(engine_context).allocator(),
            };
        }
        fn alloc(context: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
            const allocator = Backing(context);
            const result = allocator.vtable.alloc(allocator.ptr, len, alignment, ret_addr);
            if (result) |ptr| {
                Tracy.MemAlloc(pool, ptr, len);
                CountsOf(context).Took(alloc_type, len);
            }
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
            if (resized) CountsOf(context).Changed(alloc_type, memory.len, new_len);
            return resized;
        }
        fn remap(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, return_address: usize) ?[*]u8 {
            const allocator = Backing(context);
            Tracy.MemFree(pool, memory.ptr);
            const result = allocator.vtable.remap(allocator.ptr, memory, alignment, new_len, return_address);
            if (result) |ptr| {
                Tracy.MemAlloc(pool, ptr, new_len);
                CountsOf(context).Changed(alloc_type, memory.len, new_len);
            } else {
                Tracy.MemAlloc(pool, memory.ptr, memory.len);
            }
            return result;
        }
        fn free(context: *anyopaque, old_memory: []u8, alignment: std.mem.Alignment, return_address: usize) void {
            const allocator = Backing(context);
            Tracy.MemFree(pool, old_memory.ptr);
            CountsOf(context).Gave(alloc_type, old_memory.len);
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
