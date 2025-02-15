const std = @import("std");
const Set = @import("../Vendor/ziglang-set/src/hash_set/managed.zig").HashSetManaged;
const SparseSet = @import("../Vendor/zig-sparse-set/src/sparse_set.zig").SparseSet;

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
            std.debug.assert(self.mComponents.hasSparse(original_entity_id));
            std.debug.assert(!self.mComponents.hasSparse(new_entity_id));

            const new_dense_ind = self.mComponents.add(new_entity_id);
            self.mComponents.getValueByDense(new_dense_ind).* = self.mComponents.getValueBySparse(original_entity_id).*;
        }
        pub fn AddComponent(self: *Self, entityID: u32, component: ?componentType) !*componentType {
            std.debug.assert(!self.mComponents.hasSparse(entityID));

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
            std.debug.assert(self.mComponents.hasSparse(entityID));

            self.mComponents.remove(entityID);
        }
        pub fn HasComponent(self: Self, entityID: u32) bool {
            return self.mComponents.hasSparse(entityID);
        }
        pub fn GetComponent(self: Self, entityID: u32) *componentType {
            std.debug.assert(self.mComponents.hasSparse(entityID));

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
