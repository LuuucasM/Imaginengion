const std = @import("std");
const Set = @import("../Vendor/ziglang-set/src/hash_set/managed.zig").HashSetManaged;
const SparseSet = @import("../Vendor/zig-sparse-set/src/sparse_set.zig").SparseSet;

pub const IComponentArray = struct {
    ptr: *anyopaque,
    vtable: *const VTab,
    const VTab = struct {
        Deinit: *const fn (*anyopaque, std.mem.Allocator) void,
        DuplicateEntity: *const fn (*anyopaque, u32, u32) void,
        HasComponent: *const fn (*anyopaque, u32) bool,
        RemoveComponent: *const fn (*anyopaque, u32) anyerror!void,
    };

    pub fn Init(obj: anytype) IComponentArray {
        const Ptr = @TypeOf(obj);
        const PtrInfo = @typeInfo(Ptr);
        std.debug.assert(PtrInfo == .pointer);
        std.debug.assert(PtrInfo.pointer.size == .one);
        std.debug.assert(@typeInfo(PtrInfo.pointer.child) == .@"struct");

        const impl = struct {
            fn Deinit(ptr: *anyopaque, allocator: std.mem.Allocator) void {
                const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
                self.Deinit();
                allocator.destroy(self);
            }
            fn DuplicateEntity(ptr: *anyopaque, original_entity_id: u32, new_entity_id: u32) void {
                const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
                self.DuplicateEntity(original_entity_id, new_entity_id);
            }
            fn HasComponent(ptr: *anyopaque, entityID: u32) bool {
                const self = @as(Ptr, @alignCast(@ptrCast(ptr)));
                return self.HasComponent(entityID);
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
                .DuplicateEntity = impl.DuplicateEntity,
                .HasComponent = impl.HasComponent,
                .RemoveComponent = impl.RemoveComponent,
            },
        };
    }

    pub fn Deinit(self: IComponentArray, allocator: std.mem.Allocator) void {
        self.vtable.Deinit(self.ptr, allocator);
    }
    pub fn DuplicateEntity(self: IComponentArray, original_entity_id: u32, new_entity_id: u32) void {
        self.vtable.DuplicateEntity(self.ptr, original_entity_id, new_entity_id);
    }
    pub fn RemoveComponent(self: IComponentArray, entityID: u32) anyerror!void {
        try self.vtable.RemoveComponent(self.ptr, entityID);
    }
    pub fn HasComponent(self: IComponentArray, entityID: u32) bool {
        return self.vtable.HasComponent(self.ptr, entityID);
    }
};

pub fn ComponentArray(comptime componentType: type) type {
    return struct {
        const Self = @This();

        mComponents: SparseSet(.{
            .SparseT = u32,
            .DenseT = u32,
            .ValueT = componentType,
            .value_layout = .InternalArrayOfStructs,
            .allow_resize = .ResizeAllowed,
        }),

        pub fn Init(allocator: std.mem.Allocator) !Self {
            return .{
                .mComponents = try SparseSet(.{
                    .SparseT = u32,
                    .DenseT = u32,
                    .ValueT = componentType,
                    .value_layout = .InternalArrayOfStructs,
                    .allow_resize = .ResizeAllowed,
                }).init(allocator, 20, 10),
            };
        }
        pub fn Deinit(self: *Self) void {
            self.mComponents.deinit();
        }
        pub fn DuplicateEntity(self: *Self, original_entity_id: u32, new_entity_id: u32) void {
            const new_dense_ind = self.mComponents.add(new_entity_id);
            self.mComponents.getValueByDense(new_dense_ind).* = self.mComponents.getValueBySparse(original_entity_id).*;
        }
        pub fn AddComponent(self: *Self, entityID: u32, component: ?componentType) !*componentType {
            const dense_ind = self.mComponents.add(entityID);

            const new_component = self.mComponents.getValueByDense(dense_ind);

            if (component) |comp| {
                new_component.* = comp;
            } else {
                new_component.* = componentType{};
            }

            return new_component;
        }
        pub fn RemoveComponent(self: *Self, entityID: u32) !void {
            self.mComponents.remove(entityID);
        }
        pub fn HasComponent(self: Self, entityID: u32) bool {
            return self.mComponents.hasSparse(entityID);
        }
        pub fn GetComponent(self: Self, entityID: u32) *componentType {
            return self.mComponents.getValueBySparse(entityID);
        }
        pub fn NumOfComponents(self: *Self) usize {
            return self.mComponents.dense_count;
        }
        pub fn GetAllEntities(self: *Self, allocator: std.mem.Allocator) !std.ArrayList(u32) {
            var entity_set = std.ArrayList(u32).init(allocator);
            try entity_set.appendSlice(self.mComponents.dense_to_sparse[0..self.mComponents.dense_count]);
            return entity_set;
        }
    };
}
