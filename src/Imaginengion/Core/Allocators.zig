const std = @import("std");
const EngineContext = @import("EngineContext.zig");
const AllocType = EngineContext.AllocType;

pub inline fn MakeAllocatorVTable(comptime alloc_type: AllocType) type {
    const fns = struct {
        fn alloc(context: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
            const engine_context: *EngineContext = @ptrCast(@alignCast(context));
            const allocator = switch (alloc_type) {
                .Engine => engine_context._Internal.EngineGPA.allocator(),
                .Frame => engine_context._Internal.FrameArena.allocator(),
            };
            return allocator.vtable.alloc(allocator.ptr, len, alignment, ret_addr);
        }
        fn resize(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, return_address: usize) bool {
            const engine_context: *EngineContext = @ptrCast(@alignCast(context));
            const allocator = switch (alloc_type) {
                .Engine => engine_context._Internal.EngineGPA.allocator(),
                .Frame => engine_context._Internal.FrameArena.allocator(),
            };
            return allocator.vtable.resize(allocator.ptr, memory, alignment, new_len, return_address);
        }
        fn remap(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, return_address: usize) ?[*]u8 {
            const engine_context: *EngineContext = @ptrCast(@alignCast(context));
            const allocator = switch (alloc_type) {
                .Engine => engine_context._Internal.EngineGPA.allocator(),
                .Frame => engine_context._Internal.FrameArena.allocator(),
            };
            return allocator.vtable.remap(allocator.ptr, memory, alignment, new_len, return_address);
        }
        fn free(context: *anyopaque, old_memory: []u8, alignment: std.mem.Alignment, return_address: usize) void {
            const engine_context: *EngineContext = @ptrCast(@alignCast(context));
            const allocator = switch (alloc_type) {
                .Engine => engine_context._Internal.EngineGPA.allocator(),
                .Frame => engine_context._Internal.FrameArena.allocator(),
            };
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
