const std = @import("std");
const Set = @import("../Vendor/ziglang-set/src/hash_set/managed.zig").HashSetManaged;
const SparseSet = @import("../Core/SparseSet.zig").SparseSet;
const EngineContext = @import("../Core/EngineContext.zig");

pub fn InternalComponentArray(comptime entity_t: type, comptime component_type: type) type {
    return struct {
        const ECSEventManager = @import("ECSEventManager.zig").ECSEventManager(entity_t);
        const Self = @This();

        mComponents: SparseSet(entity_t, u20, component_type) = .empty,

        pub fn Deinit(self: *Self, engine_context: *EngineContext) !void {
            for (self.mComponents.mValues.items) |component| {
                component.Deinit(engine_context);
            }
            self.mComponents.deinit();
        }
        pub fn DuplicateEntity(self: *Self, original_entity_id: entity_t, new_entity_id: entity_t) void {
            std.debug.assert(self.mComponents.HasSparse(original_entity_id));
            std.debug.assert(self.mComponents.HasSparse(new_entity_id));

            self.mComponents.GetValueBySparse(new_entity_id).* = self.mComponents.GetValueBySparse(original_entity_id).*;
        }
        pub fn AddComponent(self: *Self, engine_allocator: std.mem.Allocator, entity_id: entity_t, component: component_type) !*component_type {
            std.debug.assert(!self.mComponents.HasSparse(entity_id));

            return self.mComponents.AddValue(engine_allocator, entity_id, component);
        }
        pub fn RemoveComponent(self: *Self, engine_context: *EngineContext, entityID: entity_t) !void {
            std.debug.assert(self.mComponents.HasSparse(entityID));
            const component = self.mComponents.GetValueBySparse(entityID);
            try component.Deinit(engine_context);
            self.mComponents.Remove(entityID);
        }
        pub fn HasComponent(self: Self, entityID: entity_t) bool {
            return self.mComponents.HasSparse(entityID);
        }
        pub fn GetComponent(self: Self, entity_id: entity_t) ?*component_type {
            if (self.mComponents.HasSparse(entity_id)) {
                return self.mComponents.GetValueBySparse(entity_id);
            }
            return null;
        }
        pub fn GetComponentRaw(self: Self, enttiy_id: entity_t) *component_type {
            return self.mComponents.GetValueBySparse(enttiy_id);
        }
        pub fn ResetComponent(self: *Self, engine_context: *EngineContext, entity_id: entity_t, component: component_type) void {
            const comp = self.mComponents.GetValueBySparse(entity_id);
            try comp.Deinit(engine_context);
            self.mComponents.GetValueBySparse(entity_id).* = component;
        }
        pub fn NumOfComponents(self: *Self) usize {
            return self.mComponents.mValues.items.len;
        }
        pub fn GetAllEntities(self: *Self, allocator: std.mem.Allocator) !std.ArrayList(entity_t) {
            var entity_set = std.ArrayList(entity_t){};
            try entity_set.appendSlice(allocator, self.mComponents.mDenseToSparse.items);
            return entity_set;
        }
        pub fn clearAndFree(self: *Self, engine_context: *EngineContext) !void {
            for (self.mComponents.mValues.items) |component| {
                try component.Deinit(engine_context);
            }
            self.mComponents.clearAndFree();
        }
        pub fn DestroyEntity(self: *Self, engine_context: *EngineContext, entity_id: entity_t) anyerror!void {
            std.debug.assert(self.mComponents.HasSparse(entity_id));
            try self.RemoveComponent(engine_context, entity_id);
        }
    };
}
