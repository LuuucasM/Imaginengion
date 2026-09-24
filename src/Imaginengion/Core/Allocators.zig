const std = @import("std");
const EngineContext = @import("EngineContext.zig");
const AllocType = EngineContext.AllocType;
const Tracy = @import("Tracy.zig");

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
                .Frame => engine_context._Internal.FrameArena.allocator(),
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
