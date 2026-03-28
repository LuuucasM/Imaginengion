const std = @import("std");
const InternalComponentArray = @import("InternalComponentArray.zig").InternalComponentArray;
const ComponentArray = @import("ComponentArray.zig").ComponentArray;
const StaticSkipField = @import("../Core/SkipField.zig").StaticSkipField;
const HashSet = @import("../Vendor/ziglang-set/src/hash_set/managed.zig").HashSetManaged;
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const ECSEventData = @import("../Events/ECSEventData.zig");

pub const GroupQuery = union(enum) {
    And: []const GroupQuery,
    Or: []const GroupQuery,
    Not: struct {
        mFirst: GroupQuery,
        mSecond: GroupQuery,
    },
    Component: type,
};

pub fn ComponentManager(entity_t: type, comptime components_types: []const type) type {
    return struct {
        pub const ECSEventManager = @import("../Events/EventManager.zig").EventManager(ECSEventData.EventCategories, ECSEventData.EventT(entity_t));
        pub const ParentComponent = @import("Components.zig").ParentComponent(entity_t);
        pub const ChildComponent = @import("Components.zig").ChildComponent(entity_t);
        pub const SkipFieldComponent = @import("Components.zig").SkipFieldComponent(components_types.len);

        const Self = @This();

        mComponentsArrays: std.ArrayList(ComponentArray(entity_t)) = .{},

        pub fn Init(self: *Self, engine_allocator: std.mem.Allocator) !void {

            //add the components for entity hiearchy
            const parent_array = try ComponentArray(entity_t).Init(engine_allocator, ParentComponent);
            try self.mComponentsArrays.append(engine_allocator, parent_array);

            const child_array = try ComponentArray(entity_t).Init(engine_allocator, ChildComponent);
            try self.mComponentsArrays.append(engine_allocator, child_array);

            const skip_array = try ComponentArray(entity_t).Init(engine_allocator, SkipFieldComponent);
            try self.mComponentsArrays.append(engine_allocator, skip_array);

            inline for (components_types) |component_type| {
                const new_component_array = try ComponentArray(entity_t).Init(engine_allocator, component_type);
                try self.mComponentsArrays.append(engine_allocator, new_component_array);
            }
        }

        pub fn Deinit(self: *Self, engine_context: *EngineContext) !void {
            //delete component arrays
            for (self.mComponentsArrays.items) |component_array| {
                try component_array.Deinit(engine_context);
            }

            self.mComponentsArrays.deinit(engine_context.EngineAllocator());
        }

        pub fn clearAndFree(self: *Self, engine_context: *EngineContext) void {
            for (self.mComponentsArrays.items) |component_array| {
                component_array.clearAndFree(engine_context);
            }
        }

        pub fn CreateEntity(self: *Self, engine_allocator: std.mem.Allocator, entity_id: entity_t) !void {
            _ = try self.AddComponent(engine_allocator, entity_id, SkipFieldComponent{});
        }

        pub fn DestroyEntity(self: *Self, engine_context: *EngineContext, entity_id: entity_t) !void {
            // Remove all components from this entity
            const entity_skipfield_comp = self.GetComponent(SkipFieldComponent, entity_id).?;

            var field_iter = entity_skipfield_comp.mSkipField.Iterator();
            while (field_iter.Next()) |comp_arr_ind| {
                try self.mComponentsArrays.items[comp_arr_ind].DestroyEntity(engine_context, entity_id);
            }
        }

        pub fn DuplicateEntity(self: *Self, original_entity_id: entity_t, new_entity_id: entity_t) !void {
            self.CreateEntity(new_entity_id);

            const original_skipfield_comp = self.GetComponent(SkipFieldComponent, original_entity_id).?;

            var field_iter = original_skipfield_comp.mSkipField.Iterator();
            while (field_iter.Next()) |comp_arr_ind| {
                self.mComponentsArrays.items[comp_arr_ind].DuplicateEntity(original_entity_id, new_entity_id);
            }
        }

        pub fn AddComponent(self: *Self, engine_allocator: std.mem.Allocator, entity_id: entity_t, component: anytype) !*@TypeOf(component) {
            const component_t = @TypeOf(component);
            std.debug.assert(!self.HasComponent(component_t, entity_id));

            const entity_skipfield = self.GetComponent(SkipFieldComponent, entity_id).?;
            entity_skipfield.mSkipField.ChangeToUnskipped(component_t.Ind);

            const internal_array: *InternalComponentArray(entity_t, component_t) = @ptrCast(@alignCast(self.mComponentsArrays.items[component_t.Ind].mPtr));

            return try internal_array.AddComponent(engine_allocator, entity_id, component);
        }

        pub fn RemoveComponent(self: *Self, engine_context: *EngineContext, entity_id: entity_t, component_ind: usize) !void {
            std.debug.assert(self.mComponentsArrays.items[component_ind].HasComponent(entity_id));
            std.debug.assert(component_ind < components_types.len + 3);

            const entity_skipfield = self.GetComponent(SkipFieldComponent, entity_id);
            entity_skipfield.mSkipField.ChangeToSkipped(@intCast(component_ind));

            try self.mComponentsArrays.items[component_ind].RemoveComponent(engine_context, entity_id);
        }

        pub fn HasComponent(self: Self, comptime component_type: type, entityID: entity_t) bool {
            const internal_array_t = InternalComponentArray(entity_t, component_type);
            const internal_array: *internal_array_t = @ptrCast(@alignCast(self.mComponentsArrays.items[component_type.Ind].mPtr));

            return internal_array.HasComponent(entityID);
        }

        pub fn GetComponent(self: Self, comptime component_type: type, entityID: entity_t) ?*component_type {
            const internal_array_t = InternalComponentArray(entity_t, component_type);
            const internal_array: *internal_array_t = @ptrCast(@alignCast(self.mComponentsArrays.items[component_type.Ind].mPtr));

            return internal_array.GetComponent(entityID);
        }

        pub fn ResetComponent(self: Self, engine_context: *EngineContext, entity_id: entity_t, component: anytype) void {
            const component_t = @TypeOf(component);
            std.debug.assert(self.HasComponent(component_t, entity_id));

            const internal_array_t = InternalComponentArray(entity_t, component_t);
            const internal_array: *internal_array_t = @ptrCast(@alignCast(self.mComponentsArrays.items[component_t.Ind].mPtr));

            internal_array.ResetComponent(engine_context, entity_id, component);
        }

        pub fn HasFreeEntity(self: Self) ?entity_t {
            const internal_array_t = InternalComponentArray(entity_t, SkipFieldComponent.StaticSkipFieldT);
            const skipfield_array: *internal_array_t = @ptrCast(@alignCast(self.mComponentsArrays.items[SkipFieldComponent.Ind].mPtr));
            return skipfield_array.mComponents.HasFreeEntity();
        }

        pub fn IsActiveEntity(self: Self, entity_id: entity_t) bool {
            const internal_array_t = InternalComponentArray(entity_t, SkipFieldComponent.StaticSkipFieldT);
            const skipfield_array: *internal_array_t = @ptrCast(@alignCast(self.mComponentsArrays.items[SkipFieldComponent.Ind].mPtr));

            return skipfield_array.mComponents.HasSparse(entity_id);
        }

        pub fn GetGroupMask(comptime query: GroupQuery) SkipFieldComponent.StaticSkipFieldT.SkipFieldVector {
            switch (query) {
                .Component => |component_type| {
                    var result = SkipFieldComponent.StaticSkipFieldT.NoSkipArr;
                    result[component_type.Ind] = 1;
                    return result;
                },
                .Not => |not| {
                    return GetGroupMask(not.mFirst);
                },
                .Or => |ors| {
                    var result = GetGroupMask(ors[0]);
                    inline for (ors[1..]) |or_query| {
                        const intermediate = GetGroupMask(or_query);
                        result = result & intermediate;
                    }
                    return result;
                },
                .And => |ands| {
                    var result = GetGroupMask(ands[0]);
                    inline for (ands[1..]) |and_query| {
                        const intermediate = GetGroupMask(and_query);
                        result = result | intermediate;
                    }
                    return result;
                },
            }
        }

        pub fn GetGroup(self: Self, comptime query: GroupQuery, mask: *const SkipFieldComponent.StaticSkipFieldT.SkipFieldVector, allocator: std.mem.Allocator) !std.ArrayList(entity_t) {
            switch (query) {
                .Component => |component_type| {
                    const internal_array_t = InternalComponentArray(entity_t, component_type);
                    const internal_array: *internal_array_t = @ptrCast(@alignCast(self.mComponentsArrays.items[component_type.Ind].mPtr));

                    var result = try internal_array.GetAllEntities(allocator);

                    try self.EntityListMask(&result, mask, allocator);

                    return result;
                },
                .Not => |not| {
                    var result = try self.GetGroup(not.mFirst, mask, allocator);
                    var second = try self.GetGroup(not.mSecond, mask, allocator);
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

        pub fn EntityListMask(self: Self, result: *std.ArrayList(entity_t), mask: *const SkipFieldComponent.StaticSkipFieldT.SkipFieldVector, allocator: std.mem.Allocator) !void {
            const zone = Tracy.ZoneInit("CompMan EntityListMask", @src());
            defer zone.Deinit();

            if (@reduce(.Or, mask.*) == 0) return;
            if (result.items.len == 0) return;

            var end_index: usize = result.items.len;
            var i: usize = 0;
            while (i < end_index) {
                const entity_id = result.items[i];
                const skip_comp = self.GetComponent(SkipFieldComponent, entity_id).?;
                if (!skip_comp.mSkipField.TestZerosMask(mask)) {
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
                if (result_set.contains(entity_id) == false) {
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
