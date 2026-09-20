const std = @import("std");
const InternalComponentArray = @import("InternalComponentArray.zig").InternalComponentArray;
const ComponentArray = @import("ComponentArray.zig").ComponentArray;
const BuiltinComponentCount = @import("Components.zig").BuiltinComponentCount;
const MainObjectComponent = @import("Components.zig").MainObjectComponent;
const EntityTagComponent = @import("Components.zig").EntityTagComponent;
const ScriptTagComponent = @import("Components.zig").ScriptTagComponent;
const HashSet = @import("../Vendor/ziglang-set/src/hash_set/managed.zig").HashSetManaged;
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const GroupQuery = @import("ECSManager.zig").GroupQuery;

pub fn ComponentManager(entity_t: type, comptime components_types: []const type) type {
    return struct {
        pub const ParentComponent = @import("Components.zig").ParentComponent(entity_t);
        pub const ChildComponent = @import("Components.zig").ChildComponent(entity_t);
        pub const SkipFieldComponent = @import("Components.zig").SkipFieldComponent(components_types.len);

        const Self = @This();

        const SkipFieldArrayT = InternalComponentArray(entity_t, SkipFieldComponent);

        /// A component's slot in this manager's arrays. Builtin components sit at fixed
        /// indices; every other component's slot is its position in THIS manager's
        /// components_types, which is what lets one component type be shared by several
        /// managers that list it at different positions.
        pub fn ComponentInd(comptime component_type: type) usize {
            if (component_type == ParentComponent) return ParentComponent.Ind;
            if (component_type == ChildComponent) return ChildComponent.Ind;
            if (component_type == SkipFieldComponent) return SkipFieldComponent.Ind;
            if (component_type == MainObjectComponent) return MainObjectComponent.Ind;
            if (component_type == EntityTagComponent) return EntityTagComponent.Ind;
            if (component_type == ScriptTagComponent) return ScriptTagComponent.Ind;
            inline for (components_types, 0..) |list_type, i| {
                if (list_type == component_type) return i + BuiltinComponentCount;
            }
            @compileError(@typeName(component_type) ++ " is not in this manager's components list");
        }

        pub const empty: Self = .{
            .mComponentsArrays = .empty,
        };

        mComponentsArrays: std.ArrayList(ComponentArray(entity_t)),

        pub fn Init(self: *Self, engine_allocator: std.mem.Allocator) !void {

            //add the components for entity hiearchy
            const parent_array = try ComponentArray(entity_t).Init(engine_allocator, ParentComponent);
            try self.mComponentsArrays.append(engine_allocator, parent_array);

            const child_array = try ComponentArray(entity_t).Init(engine_allocator, ChildComponent);
            try self.mComponentsArrays.append(engine_allocator, child_array);

            const skip_array = try ComponentArray(entity_t).Init(engine_allocator, SkipFieldComponent);
            try self.mComponentsArrays.append(engine_allocator, skip_array);

            const main_object_array = try ComponentArray(entity_t).Init(engine_allocator, MainObjectComponent);
            try self.mComponentsArrays.append(engine_allocator, main_object_array);

            const entity_tag_array = try ComponentArray(entity_t).Init(engine_allocator, EntityTagComponent);
            try self.mComponentsArrays.append(engine_allocator, entity_tag_array);

            const script_tag_array = try ComponentArray(entity_t).Init(engine_allocator, ScriptTagComponent);
            try self.mComponentsArrays.append(engine_allocator, script_tag_array);

            std.debug.assert(self.mComponentsArrays.items.len == BuiltinComponentCount);

            inline for (components_types) |component_type| {
                const new_component_array = try ComponentArray(entity_t).Init(engine_allocator, component_type);
                try self.mComponentsArrays.append(engine_allocator, new_component_array);
            }
        }

        pub fn Deinit(self: *Self, engine_context: *EngineContext) void {
            for (self.mComponentsArrays.items) |component_array| {
                component_array.Deinit(engine_context);
            }

            self.mComponentsArrays.deinit(engine_context.EngineAllocator());
        }

        pub fn clearAndFree(self: *Self, engine_context: *EngineContext) void {
            for (self.mComponentsArrays.items) |component_array| {
                component_array.clearAndFree(engine_context);
            }
        }

        /// Reuses the most recently destroyed id (generation already incremented) and gives it its SkipFieldComponent.
        /// Returns null if there are no destroyed ids to reuse. Never allocates, so it cannot fail halfway.
        pub fn ReuseFreeEntity(self: *Self) ?entity_t {
            return self._SkipFieldArray().mComponents.AddValueToFreeID(_NewSkipField());
        }

        /// Gives a never before used id its SkipFieldComponent. Only valid when ReuseFreeEntity returned null.
        pub fn CreateNewEntity(self: *Self, engine_allocator: std.mem.Allocator, entity_id: entity_t) !void {
            _ = try self._SkipFieldArray().AddComponent(engine_allocator, entity_id, _NewSkipField());
        }

        pub fn DestroyEntity(self: *Self, engine_context: *EngineContext, entity_id: entity_t) void {
            // iterate a copy of the skipfield because removing the SkipFieldComponent swap-removes it
            // inside its array, which would move another entity's skipfield under the iterator
            var entity_skipfield = self.GetComponent(SkipFieldComponent, entity_id).?.mSkipField;

            var field_iter = entity_skipfield.Iterator();
            while (field_iter.next()) |comp_arr_ind| {
                if (comp_arr_ind == SkipFieldComponent.Ind) continue;
                self.mComponentsArrays.items[comp_arr_ind].DestroyEntity(engine_context, entity_id);
            }

            // remove the skipfield last so the entity stays active while its other components deinit.
            // this also puts the id on the skipfield sparse set's free list for ReuseFreeEntity
            self.mComponentsArrays.items[SkipFieldComponent.Ind].DestroyEntity(engine_context, entity_id);
        }

        fn _SkipFieldArray(self: Self) *SkipFieldArrayT {
            return @ptrCast(@alignCast(self.mComponentsArrays.items[SkipFieldComponent.Ind].mPtr));
        }

        fn _NewSkipField() SkipFieldComponent {
            var new_skipfield = SkipFieldComponent{};
            // the skipfield tracks itself so it shows up in queries and gets removed in DestroyEntity
            new_skipfield.mSkipField.ChangeToUnskipped(SkipFieldComponent.Ind);
            return new_skipfield;
        }

        /// Deep copies every component array into `other`, which must be initialized and empty.
        /// Entity ids, their generations and the free id list all carry over, so the copy holds the
        /// same entities under the same ids.
        pub fn CopyInto(self: *Self, engine_context: *EngineContext, other: *Self) !void {
            std.debug.assert(other.mComponentsArrays.items.len == self.mComponentsArrays.items.len);

            var copied: usize = 0;
            errdefer {
                // the arrays already copied own their components, so they are emptied again
                // rather than left as a half built ECS
                for (other.mComponentsArrays.items[0..copied]) |component_array| {
                    component_array.clearAndFree(engine_context);
                }
            }
            while (copied < self.mComponentsArrays.items.len) : (copied += 1) {
                try self.mComponentsArrays.items[copied].CopyInto(engine_context, other.mComponentsArrays.items[copied]);
            }
        }

        /// Copies the original's components onto an already created entity.
        /// The hierarchy components and the entity/script tag are left out: the caller owns those,
        /// because a copy belongs in its own place in the hierarchy rather than the original's.
        pub fn DuplicateEntity(self: *Self, engine_context: *EngineContext, original_entity_id: entity_t, new_entity_id: entity_t) !void {
            std.debug.assert(self.IsActiveEntity(original_entity_id));
            std.debug.assert(self.IsActiveEntity(new_entity_id));

            // a copy of the skipfield, because the arrays below move as components are added
            var original_skipfield = self.GetComponent(SkipFieldComponent, original_entity_id).?.mSkipField;

            var field_iter = original_skipfield.Iterator();
            while (field_iter.next()) |comp_arr_ind| {
                if (comp_arr_ind == ParentComponent.Ind) continue;
                if (comp_arr_ind == ChildComponent.Ind) continue;
                if (comp_arr_ind == SkipFieldComponent.Ind) continue;
                if (comp_arr_ind == EntityTagComponent.Ind) continue;
                if (comp_arr_ind == ScriptTagComponent.Ind) continue;

                try self.mComponentsArrays.items[comp_arr_ind].DuplicateEntity(engine_context, original_entity_id, new_entity_id);

                // the copy tracks its own components, and the skipfield is refetched because that add moved things
                self.GetComponent(SkipFieldComponent, new_entity_id).?.mSkipField.ChangeToUnskipped(comp_arr_ind);
            }
        }

        pub fn AddComponent(self: *Self, engine_allocator: std.mem.Allocator, entity_id: entity_t, component: anytype) !*@TypeOf(component) {
            const component_t = @TypeOf(component);
            std.debug.assert(!self.HasComponent(component_t, entity_id));

            const entity_skipfield = self.GetComponent(SkipFieldComponent, entity_id).?;
            entity_skipfield.mSkipField.ChangeToUnskipped(ComponentInd(component_t));

            const internal_array: *InternalComponentArray(entity_t, component_t) = @ptrCast(@alignCast(self.mComponentsArrays.items[ComponentInd(component_t)].mPtr));

            return try internal_array.AddComponent(engine_allocator, entity_id, component);
        }

        pub fn RemoveComponent(self: *Self, engine_context: *EngineContext, entity_id: entity_t, component_ind: usize) void {
            std.debug.assert(component_ind < components_types.len + BuiltinComponentCount);
            std.debug.assert(component_ind != SkipFieldComponent.Ind); // only removed through DestroyEntity
            std.debug.assert(self.mComponentsArrays.items[component_ind].HasComponent(entity_id));

            const entity_skipfield = self.GetComponent(SkipFieldComponent, entity_id).?;
            entity_skipfield.mSkipField.ChangeToSkipped(component_ind);

            self.mComponentsArrays.items[component_ind].RemoveComponent(engine_context, entity_id);
        }

        pub fn HasComponent(self: Self, comptime component_type: type, entityID: entity_t) bool {
            const internal_array_t = InternalComponentArray(entity_t, component_type);
            const internal_array: *internal_array_t = @ptrCast(@alignCast(self.mComponentsArrays.items[ComponentInd(component_type)].mPtr));

            return internal_array.HasComponent(entityID);
        }

        pub fn GetComponent(self: Self, comptime component_type: type, entityID: entity_t) ?*component_type {
            const internal_array_t = InternalComponentArray(entity_t, component_type);
            const internal_array: *internal_array_t = @ptrCast(@alignCast(self.mComponentsArrays.items[ComponentInd(component_type)].mPtr));

            return internal_array.GetComponent(entityID);
        }

        pub fn ResetComponent(self: Self, engine_context: *EngineContext, entity_id: entity_t, component: anytype) void {
            const component_t = @TypeOf(component);
            std.debug.assert(self.HasComponent(component_t, entity_id));

            const internal_array_t = InternalComponentArray(entity_t, component_t);
            const internal_array: *internal_array_t = @ptrCast(@alignCast(self.mComponentsArrays.items[ComponentInd(component_t)].mPtr));

            internal_array.ResetComponent(engine_context, entity_id, component);
        }

        pub fn IsActiveEntity(self: Self, entity_id: entity_t) bool {
            return self._SkipFieldArray().mComponents.HasSparse(entity_id);
        }

        //provides a mask for a group query
        pub fn GetGroupMask(comptime query: GroupQuery) SkipFieldComponent.StaticSkipFieldT {
            switch (query) {
                .Component => |component_type| {
                    var empty_field: SkipFieldComponent.StaticSkipFieldT = .AllSkip;
                    empty_field.ChangeToUnskipped(ComponentInd(component_type));
                    return empty_field;
                },
                .Not => |not| {
                    var result_first = GetGroupMask(not.mFirst.*);
                    const result_second = GetGroupMask(not.mSecond.*);
                    result_first.Difference(&result_second);
                    return result_first;
                },
                .Or => |ors| {
                    var result = GetGroupMask(ors[0]);
                    inline for (ors[1..]) |or_query| {
                        const intermediate = GetGroupMask(or_query);
                        result.Union(&intermediate);
                    }
                    return result;
                },
                .And => |ands| {
                    var result = GetGroupMask(ands[0]);
                    inline for (ands[1..]) |and_query| {
                        const intermediate = GetGroupMask(and_query);
                        result.Intersect(&intermediate);
                    }
                    return result;
                },
            }
        }

        pub fn GetGroup(self: Self, comptime query: GroupQuery, mask: *const SkipFieldComponent.StaticSkipFieldT, allocator: std.mem.Allocator) !std.ArrayList(entity_t) {
            switch (query) {
                .Component => |component_type| {
                    const internal_array_t = InternalComponentArray(entity_t, component_type);
                    const internal_array: *internal_array_t = @ptrCast(@alignCast(self.mComponentsArrays.items[ComponentInd(component_type)].mPtr));

                    var result = try internal_array.GetAllEntities(allocator);

                    try self.EntityListMask(&result, mask, allocator);

                    return result;
                },
                .Not => |not| {
                    var result = try self.GetGroup(not.mFirst.*, mask, allocator);
                    var second = try self.GetGroup(not.mSecond.*, mask, allocator);
                    defer second.deinit(allocator);
                    try self.EntityListDifference(&result, second, allocator);
                    return result;
                },
                .Or => |ors| {
                    var result = try self.GetGroup(ors[0], mask, allocator);
                    inline for (ors[1..]) |or_query| {
                        var intermediate = try self.GetGroup(or_query, mask, allocator);
                        defer intermediate.deinit(allocator);
                        try self.EntityListUnion(&result, intermediate, allocator);
                    }
                    return result;
                },
                .And => |ands| {
                    var result = try self.GetGroup(ands[0], mask, allocator);
                    inline for (ands[1..]) |and_query| {
                        var intermediate = try self.GetGroup(and_query, mask, allocator);
                        defer intermediate.deinit(allocator);
                        try self.EntityListIntersection(&result, intermediate, allocator);
                    }
                    return result;
                },
            }
        }

        pub fn EntityListMask(self: Self, result: *std.ArrayList(entity_t), mask: *const SkipFieldComponent.StaticSkipFieldT, allocator: std.mem.Allocator) !void {
            const zone = Tracy.ZoneInit("CompMan EntityListMask", @src());
            defer zone.Deinit();

            // a mask that requires nothing keeps every entity, so there is nothing to filter out
            if (mask.mNumUnskipped == 0) return;
            if (result.items.len == 0) return;

            const internal_array_t = InternalComponentArray(entity_t, SkipFieldComponent);
            const internal_array: *internal_array_t = @ptrCast(@alignCast(self.mComponentsArrays.items[SkipFieldComponent.Ind].mPtr));

            var end_index: usize = result.items.len;
            var i: usize = 0;
            while (i < end_index) {
                const entity_id = result.items[i];
                const skip_comp = internal_array.GetComponent(entity_id).?;
                if (!skip_comp.mSkipField.IsUnskippedSuperSet(mask)) {
                    result.items[i] = result.items[end_index - 1];
                    end_index -= 1;
                } else {
                    i += 1;
                }
            }

            result.shrinkAndFree(allocator, end_index);
        }

        pub fn EntityListDifference(_: Self, result: *std.ArrayList(entity_t), list2: std.ArrayList(entity_t), allocator: std.mem.Allocator) !void {
            const zone = Tracy.ZoneInit("CompMan EntityListDifference", @src());
            defer zone.Deinit();

            if (result.items.len == 0) return;

            var list2_set = HashSet(entity_t).init(allocator);
            defer list2_set.deinit();
            _ = try list2_set.appendSlice(list2.items);

            var end_index: usize = result.items.len;
            var i: usize = 0;
            while (i < end_index) {
                if (list2_set.contains(result.items[i]) == true) {
                    result.items[i] = result.items[end_index - 1];
                    end_index -= 1;
                } else {
                    i += 1;
                }
            }

            result.shrinkAndFree(allocator, end_index);
        }

        pub fn EntityListUnion(_: Self, result: *std.ArrayList(entity_t), list2: std.ArrayList(entity_t), allocator: std.mem.Allocator) !void {
            const zone = Tracy.ZoneInit("CompMan EntityUnion", @src());
            defer zone.Deinit();

            var result_set = HashSet(entity_t).init(allocator);
            defer result_set.deinit();
            _ = try result_set.appendSlice(result.items);

            for (list2.items) |entity_id| {
                // added to the set as well, so a repeat inside list2 is not appended twice
                if ((try result_set.add(entity_id)) == true) {
                    try result.append(allocator, entity_id);
                }
            }
        }

        pub fn EntityListIntersection(_: Self, result: *std.ArrayList(entity_t), list2: std.ArrayList(entity_t), allocator: std.mem.Allocator) !void {
            const zone = Tracy.ZoneInit("CompMan EntityIntersection", @src());
            defer zone.Deinit();

            var list2_set = HashSet(entity_t).init(allocator);
            defer list2_set.deinit();
            _ = try list2_set.appendSlice(list2.items);

            var end_index: usize = result.items.len;
            var i: usize = 0;
            while (i < end_index) {
                if (list2_set.contains(result.items[i]) == true) {
                    i += 1;
                } else {
                    result.items[i] = result.items[end_index - 1];
                    end_index -= 1;
                }
            }

            result.shrinkAndFree(allocator, end_index);
        }
    };
}
