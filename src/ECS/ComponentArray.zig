const std = @import("std");
const SparseSet = @import("../Vendor/zig-sparse-set/src/sparse_set.zig").SparseSet;

pub const IComponentArray = struct {
    ptr: *anyopaque,
    vtable: *const VTab,
    const VTab = struct {
        Deinit: *const fn (*anyopaque, std.mem.Allocator) void,
        RemoveComponent: *const fn (*anyopaque, u32) anyerror!void,
    };

    pub fn Init(obj: anytype) IComponentArray {
        const Ptr = @TypeOf(obj);
        const PtrInfo = @typeInfo(Ptr);
        std.debug.assert(PtrInfo == .Pointer);
        std.debug.assert(PtrInfo.Pointer.size == .One);
        std.debug.assert(@typeInfo(PtrInfo.Pointer.child) == .Struct);

        const impl = struct {
            fn Deinit(ptr: *anyopaque, allocator: std.mem.Allocator) void {
                const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
                self.Deinit();
                allocator.destroy(self);
            }
            fn RemoveComponent(ptr: *anyopaque, entityID: u32) anyerror!void {
                const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
                try self.RemoveComponent(entityID);
            }
        };
        return IComponentArray{
            .ptr = obj,
            .vtable = &.{
                .Deinit = impl.Deinit,
                .RemoveComponent = impl.RemoveComponent,
            },
        };
    }

    pub fn Deinit(self: IComponentArray, allocator: std.mem.Allocator) void {
        self.vtable.Deinit(self.ptr, allocator);
    }
    pub fn RemoveComponent(self: IComponentArray, entityID: u32) anyerror!void {
        try self.vtable.RemoveComponent(self.ptr, entityID);
    }
};

pub fn ComponentArray(comptime componentType: type) type {
    return struct {
        const Self = @This();

        _Components: SparseSet(.{ .SparseT = u32, .DenseT = u32, .ValueT = componentType, .value_layout = .InternalArrayOfStructs, .allow_resize = .ResizeAllowed }),

        pub fn Init(allocator: std.mem.Allocator) !Self {
            return .{
                ._Components = try SparseSet(.{
                    .SparseT = u32,
                    .DenseT = u32,
                    .ValueT = componentType,
                    .value_layout = .InternalArrayOfStructs,
                    .allow_resize = .ResizeAllowed,
                }).init(allocator, 20, 10),
            };
        }
        pub fn Deinit(self: *Self) void {
            self._Components.deinit();
        }
        pub fn AddComponent(self: *Self, entityID: u32, component: componentType) !*componentType {
            const dense_ind = self._Components.add(entityID);
            const new_component = self._Components.getValueByDense(dense_ind);
            new_component.* = component;
            return new_component;
        }
        pub fn RemoveComponent(self: *Self, entityID: u32) !void {
            self._Components.remove(entityID);
        }
        pub fn HasComponent(self: Self, entityID: u32) bool {
            return self._Components.hasSparse(entityID);
        }
        pub fn GetComponent(self: Self, entityID: u32) *componentType {
            return self._Components.getValueBySparse(entityID);
        }
    };
}
