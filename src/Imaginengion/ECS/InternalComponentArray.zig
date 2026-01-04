const std = @import("std");
const Set = @import("../Vendor/ziglang-set/src/hash_set/managed.zig").HashSetManaged;
const SparseSet = @import("../Vendor/zig-sparse-set/src/sparse_set.zig").SparseSet;
const ComponentCategory = @import("ECSManager.zig").ComponentCategory;
const EngineContext = @import("../Core/EngineContext.zig");

pub fn ComponentArray(comptime entity_t: type, comptime component_type: type) type {
    return struct {
        const ECSEventManager = @import("ECSEventManager.zig").ECSEventManager(entity_t);
        const Self = @This();

        mComponents: SparseSet(.{
            .SparseT = entity_t,
            .DenseT = entity_t,
            .ValueT = component_type,
            .value_layout = .InternalArrayOfStructs,
            .allow_resize = .ResizeAllowed,
        }),

        pub fn Init(allocator: std.mem.Allocator) !Self {
            return .{
                .mComponents = try SparseSet(.{
                    .SparseT = entity_t,
                    .DenseT = entity_t,
                    .ValueT = component_type,
                    .value_layout = .InternalArrayOfStructs,
                    .allow_resize = .ResizeAllowed,
                }).init(allocator, 20, 10),
            };
        }
        pub fn Deinit(self: *Self, engine_context: *EngineContext) !void {
            var i: usize = 0;
            while (i < self.mComponents.dense_count) : (i += 1) {
                try self.mComponents.values[i].Deinit(engine_context);
            }
            self.mComponents.deinit();
        }
        pub fn DuplicateEntity(self: *Self, original_entity_id: entity_t, new_entity_id: entity_t) void {
            std.debug.assert(self.mComponents.HasSparse(original_entity_id));
            std.debug.assert(!self.mComponents.HasSparse(new_entity_id));

            const new_dense_ind = self.mComponents.add(new_entity_id);
            self.mComponents.getValueByDense(new_dense_ind).* = self.mComponents.getValueBySparse(original_entity_id).*;
        }
        pub fn AddComponent(self: *Self, entityID: entity_t, component: component_type) !*component_type {
            std.debug.assert(!self.mComponents.HasSparse(entityID));

            const dense_ind = self.mComponents.add(entityID);

            const new_component = self.mComponents.getValueByDense(dense_ind);

            new_component.* = component;

            return new_component;
        }
        pub fn RemoveComponent(self: *Self, engine_context: *EngineContext, entityID: entity_t) !void {
            std.debug.assert(self.mComponents.HasSparse(entityID));
            const component = self.mComponents.getValueBySparse(entityID);
            try component.Deinit(engine_context);
            self.mComponents.remove(entityID);
        }
        pub fn HasComponent(self: Self, entityID: entity_t) bool {
            return self.mComponents.HasSparse(entityID);
        }
        pub fn GetComponent(self: Self, entityID: entity_t) ?*component_type {
            if (self.mComponents.HasSparse(entityID)) {
                return self.mComponents.getValueBySparse(entityID);
            }
            return null;
        }
        pub fn GetMultiData(self: Self, entity_id: entity_t) @Vector(4, entity_t) {
            std.debug.assert(self.mComponents.HasSparse(entity_id));
            if (component_type.Category == .Multiple) {
                const component = self.mComponents.getValueBySparse(entity_id);
                return @Vector(4, entity_t){ component.mParent, component.mFirst, component.mNext, component.mPrev };
            } else {
                return @Vector(4, entity_t){ 0, 0, 0, 0 };
            }
        }
        // Conditionally include SetMultiData function based on component type
        pub fn SetMultiData(self: Self, entity_id: entity_t, multi_data: @Vector(4, entity_t)) void {
            std.debug.assert(self.mComponents.HasSparse(entity_id));
            if (component_type.Category == .Multiple) {
                const component = self.mComponents.getValueBySparse(entity_id);
                component.mParent = multi_data[0];
                component.mFirst = multi_data[1];
                component.mNext = multi_data[2];
                component.mPrev = multi_data[3];
            }
        }

        pub fn NumOfComponents(self: *Self) usize {
            return self.mComponents.dense_count;
        }
        pub fn GetAllEntities(self: *Self, allocator: std.mem.Allocator) !std.ArrayList(entity_t) {
            var entity_set = std.ArrayList(entity_t){};
            try entity_set.appendSlice(allocator, self.mComponents.dense_to_sparse[0..self.mComponents.dense_count]);
            return entity_set;
        }
        pub fn clearAndFree(self: *Self, engine_context: *EngineContext) void {
            var i: usize = 0;
            while (i < self.mComponents.dense_count) : (i += 1) {
                try self.mComponents.values[i].Deinit(engine_context);
            }
            self.mComponents.clear();
        }
        pub fn GetCategory(_: *Self) ComponentCategory {
            return component_type.Category;
        }
        pub fn DestroyEntity(self: *Self, engine_context: *EngineContext, entity_id: entity_t, ecs_event_manager: *ECSEventManager) anyerror!void {
            std.debug.assert(self.mComponents.HasSparse(entity_id));

            if (component_type.Category == .Multiple) {
                const first_component = self.mComponents.getValueBySparse(entity_id);

                var curr_id = first_component.mNext;
                var curr_component = self.mComponents.getValueBySparse(curr_id);

                //start fromt he second component in the list (if there is one) because we will manually
                //delete the first component after iterating through (possible) children

                while (curr_id != entity_id) {
                    try ecs_event_manager.Insert(engine_context.mEngineAllocator, .{ .ET_CleanMultiEntity = .{ .mEntityID = curr_id } });

                    curr_id = curr_component.mNext;
                    curr_component = self.mComponents.getValueBySparse(curr_id);
                }
            }
            try self.RemoveComponent(engine_context, entity_id);
        }
    };
}
