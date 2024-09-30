const std = @import("std");
const SparseSet = @import("../Vendor/zig-sparse-set/src/sparse_set.zig").SparseSet;
pub const IComponentArray = struct {
    ptr: *anyopaque,
};

pub fn ComponentArray(comptime componentType: type) type {
    return struct {
        const Self = @This();
        _ComponentArray: SparseSet(.{
            .SparseT = u64,
            .DenseT = u16,
            .ValueT = componentType,
            .allow_resize = .ResizeAllowed,
        }) = undefined,
        pub fn Init(self: Self, allocator: std.mem.Allocator) !void {
            try self._ComponentArray.init(allocator, 10, 10);
        }
        pub fn Deinit(self: Self) void {
            self._ComponentArray.deinit();
        }
        pub fn AddComponent(entityID: u64, component: componentType) *componentType {
            _ = entityID;
            _ = component;
        }
        pub fn RemoveComponent(entityID: u64) void {
            _ = entityID;
        }
        pub fn GetComponent(entityID: u64) *componentType {
            _ = entityID;
        }
    };
}
