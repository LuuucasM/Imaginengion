const std = @import("std");
const Set = @import("../Vendor/ziglang-set/src/hash_set/managed.zig").HashSetManaged;
const SparseSet = @import("../Vendor/zig-sparse-set/src/sparse_set.zig").SparseSet;
const ComponentCategory = @import("ECSManager.zig").ComponentCategory;

pub fn ComponentArray(comptime entity_t: type, comptime componentType: type) type {
    return struct {
        const ECSEventManager = @import("ECSEventManager.zig").ECSEventManager(entity_t);
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
        pub fn Deinit(self: *Self) !void {
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
        pub fn AddComponent(self: *Self, entityID: entity_t, component: componentType) !*componentType {
            std.debug.assert(!self.mComponents.HasSparse(entityID));

            const dense_ind = self.mComponents.add(entityID);

            const new_component = self.mComponents.getValueByDense(dense_ind);

            new_component.* = component;

            return new_component;
        }
        pub fn RemoveComponent(self: *Self, entityID: entity_t) !void {
            std.debug.assert(self.mComponents.HasSparse(entityID));
            const component = self.mComponents.getValueBySparse(entityID);
            try component.Deinit();
            self.mComponents.remove(entityID);
        }
        pub fn HasComponent(self: Self, entityID: entity_t) bool {
            return self.mComponents.HasSparse(entityID);
        }
        pub fn GetComponent(self: Self, entityID: entity_t) ?*componentType {
            if (self.mComponents.HasSparse(entityID)) {
                return self.mComponents.getValueBySparse(entityID);
            }
            return null;
        }
        pub fn NumOfComponents(self: *Self) usize {
            return self.mComponents.dense_count;
        }
        pub fn GetAllEntities(self: *Self, allocator: std.mem.Allocator) !std.ArrayList(entity_t) {
            var entity_set = std.ArrayList(entity_t){};
            try entity_set.appendSlice(allocator, self.mComponents.dense_to_sparse[0..self.mComponents.dense_count]);
            return entity_set;
        }
        pub fn clearAndFree(self: *Self) void {
            var i: usize = 0;
            while (i < self.mComponents.dense_count) : (i += 1) {
                try self.mComponents.values[i].Deinit();
            }
            self.mComponents.clear();
        }
        pub fn GetCategory(_: *Self) ComponentCategory {
            return componentType.Category;
        }
        pub fn DestroyEntity(self: *Self, entity_id: entity_t, ecs_event_manager: *ECSEventManager) anyerror!void {
            if (componentType.Category == .Multiple) {
                std.debug.assert(self.mComponents.HasSparse(entity_id));
                const component = self.mComponents.getValueBySparse(entity_id);
                var curr_id = entity_id;
                var curr_component = component;

                //step forward manually once because we dont want to call internal multi destroy
                //on the parent entity (entity_id) we want to create an event for all of the children
                curr_id = curr_component.mNext;
                curr_component = self.mComponents.getValueBySparse(curr_id);

                while (true) : (if (curr_id == component.mFirst) break) {
                    const next_id = curr_component.mNext;
                    try ecs_event_manager.Insert(.{ .ET_CleanMultiEntity = .{ .mEntityID = curr_id } });
                    if (next_id == component.mFirst) break;
                    curr_id = next_id;
                    curr_component = self.mComponents.getValueBySparse(curr_id);
                }
            }
            try self.RemoveComponent(entity_id);
        }
    };
}
