const std = @import("std");
const Set = @import("../Vendor/ziglang-set/src/hash_set/managed.zig").HashSetManaged;
const SparseSet = @import("../Vendor/zig-sparse-set/src/sparse_set.zig").SparseSet;

pub fn ComponentArray(comptime entity_t: type, comptime componentType: type) type {
    return struct {
        const Self = @This();

        mComponents: SparseSet(.{
            .SparseT = entity_t,
            .DenseT = entity_t,
            .ValueT = componentType,
            .value_layout = .InternalArrayOfStructs,
            .allow_resize = .ResizeAllowed,
        }),

        pub fn Init(allocator: std.mem.Allocator) !Self {
            return .{
                .mComponents = try SparseSet(.{
                    .SparseT = entity_t,
                    .DenseT = entity_t,
                    .ValueT = componentType,
                    .value_layout = .InternalArrayOfStructs,
                    .allow_resize = .ResizeAllowed,
                }).init(allocator, 20, 10),
            };
        }
        pub fn Deinit(self: *Self) void {
            var i: usize = 0;
            while (i < self.mComponents.dense_count) : (i += 1) {
                try self.mComponents.values[i].Deinit();
            }
            self.mComponents.deinit();
        }
        pub fn DuplicateEntity(self: *Self, original_entity_id: entity_t, new_entity_id: entity_t) void {
            std.debug.assert(self.mComponents.HasSparse(original_entity_id));
            std.debug.assert(!self.mComponents.HasSparse(new_entity_id));

            const new_dense_ind = self.mComponents.add(new_entity_id);
            self.mComponents.getValueByDense(new_dense_ind).* = self.mComponents.getValueBySparse(original_entity_id).*;
        }
        pub fn AddComponent(self: *Self, entityID: entity_t, component: ?componentType) !*componentType {
            std.debug.assert(!self.mComponents.HasSparse(entityID));

            const dense_ind = self.mComponents.add(entityID);

            const new_component = self.mComponents.getValueByDense(dense_ind);

            if (component) |comp| {
                new_component.* = comp;
            } else {
                new_component.* = componentType{};
            }

            return new_component;
        }
        pub fn RemoveComponent(self: *Self, entityID: entity_t) !void {
            std.debug.assert(self.mComponents.HasSparse(entityID));

            self.mComponents.remove(entityID);
        }
        pub fn HasComponent(self: Self, entityID: entity_t) bool {
            return self.mComponents.HasSparse(entityID);
        }
        pub fn GetComponent(self: Self, entityID: entity_t) *componentType {
            std.debug.assert(self.mComponents.HasSparse(entityID));

            return self.mComponents.getValueBySparse(entityID);
        }
        pub fn NumOfComponents(self: *Self) usize {
            return self.mComponents.dense_count;
        }
        pub fn GetAllEntities(self: *Self, allocator: std.mem.Allocator) !std.ArrayList(entity_t) {
            var entity_set = std.ArrayList(entity_t).init(allocator);
            try entity_set.appendSlice(self.mComponents.dense_to_sparse[0..self.mComponents.dense_count]);
            return entity_set;
        }
        pub fn clearAndFree(self: *Self) void {
            var i: usize = 0;
            while (i < self.mComponents.dense_count) : (i += 1) {
                try self.mComponents.values[i].Deinit();
            }
            self.mComponents.clear();
        }
    };
}
