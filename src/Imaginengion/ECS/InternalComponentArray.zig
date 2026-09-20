const std = @import("std");
const SparseSet = @import("../Core/SparseSet.zig").SparseSet;
const EngineContext = @import("../Core/EngineContext.zig");

pub fn InternalComponentArray(comptime entity_t: type, comptime component_type: type) type {
    return struct {
        const Self = @This();
        // only the component that owns entity lifetime (SkipFieldComponent) opts in to the free id list
        const track_free_ids = @hasDecl(component_type, "TrackFreeIDs") and component_type.TrackFreeIDs;
        pub const SparseSetT = SparseSet(entity_t, u20, component_type, track_free_ids);

        mComponents: SparseSetT = .empty,

        pub fn Deinit(self: *Self, engine_context: *EngineContext) !void {
            // every component is deinitialized even if one of them fails, the first error is reported after
            var first_error: ?anyerror = null;
            for (self.mComponents.mValues.items) |*component| {
                component.Deinit(engine_context) catch |err| {
                    if (first_error == null) first_error = err;
                };
            }

            self.mComponents.Deinit(engine_context.EngineAllocator());

            if (first_error) |err| return err;
        }
        pub fn DuplicateEntity(self: *Self, engine_context: *EngineContext, original_entity_id: entity_t, new_entity_id: entity_t) !void {
            std.debug.assert(self.mComponents.HasSparse(original_entity_id));

            const original_component = self.mComponents.GetValueBySparse(original_entity_id);

            // a component that owns memory copies itself, anything else is a plain value copy.
            // the copy is made before the add below, which can move the array the original lives in
            const component_copy = if (@hasDecl(component_type, "Clone"))
                try original_component.Clone(engine_context)
            else
                original_component.*;

            _ = try self.AddComponent(engine_context.EngineAllocator(), new_entity_id, component_copy);
        }
        /// Deep copies this array into `other`, which must be empty.
        /// Entity ids and the free id list carry over, so the copy is addressed by the same ids.
        pub fn CopyInto(self: *Self, engine_context: *EngineContext, other: *Self) !void {
            try self.mComponents.CopyInto(engine_context.EngineAllocator(), &other.mComponents);

            // a component that owns memory is still aliasing this array's copy, so it is replaced
            // by a real clone. anything else is already a finished value copy
            if (!@hasDecl(component_type, "Clone")) return;

            var cloned: usize = 0;
            errdefer {
                // only the finished clones own anything, the rest still alias this array
                for (other.mComponents.mValues.items[0..cloned]) |*component| {
                    component.Deinit(engine_context) catch {};
                }
                other.mComponents.clearAndFree(engine_context.EngineAllocator());
            }
            while (cloned < other.mComponents.mValues.items.len) : (cloned += 1) {
                other.mComponents.mValues.items[cloned] = try self.mComponents.mValues.items[cloned].Clone(engine_context);
            }
        }
        pub fn AddComponent(self: *Self, engine_allocator: std.mem.Allocator, entity_id: entity_t, component: component_type) !*component_type {
            std.debug.assert(!self.mComponents.HasSparse(entity_id));

            return try self.mComponents.AddValue(engine_allocator, entity_id, component);
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
        /// Asserts the entity has this component, rather than checking like GetComponent does.
        pub fn GetComponentAssume(self: Self, entity_id: entity_t) *component_type {
            return self.mComponents.GetValueBySparse(entity_id);
        }
        pub fn ResetComponent(self: *Self, engine_context: *EngineContext, entity_id: entity_t, component: component_type) !void {
            const old_component = self.mComponents.GetValueBySparse(entity_id);
            try old_component.Deinit(engine_context);
            old_component.* = component;
        }
        pub fn NumOfComponents(self: *Self) usize {
            return self.mComponents.mValues.items.len;
        }
        pub fn GetAllEntities(self: *Self, allocator: std.mem.Allocator) !std.ArrayList(entity_t) {
            var entity_set: std.ArrayList(entity_t) = .empty;
            try entity_set.appendSlice(allocator, self.mComponents.mDenseToSparse.items);
            return entity_set;
        }
        pub fn clearAndFree(self: *Self, engine_context: *EngineContext) !void {
            // every component is deinitialized even if one of them fails, the first error is reported after
            var first_error: ?anyerror = null;
            for (self.mComponents.mValues.items) |*component| {
                component.Deinit(engine_context) catch |err| {
                    if (first_error == null) first_error = err;
                };
            }

            self.mComponents.clearAndFree(engine_context.EngineAllocator());

            if (first_error) |err| return err;
        }
        pub fn DestroyEntity(self: *Self, engine_context: *EngineContext, entity_id: entity_t) anyerror!void {
            std.debug.assert(self.mComponents.HasSparse(entity_id));
            try self.RemoveComponent(engine_context, entity_id);
        }
    };
}
