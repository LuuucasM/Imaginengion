const std = @import("std");
const InternalComponentArray = @import("InternalComponentArray.zig").ComponentArray;
const ComponentArray = @import("ComponentArray.zig").ComponentArray;
const StaticSkipField = @import("../Core/SkipField.zig").StaticSkipField;
const SparseSet = @import("../Vendor/zig-sparse-set/src/sparse_set.zig").SparseSet;
const HashSet = @import("../Vendor/ziglang-set/src/hash_set/managed.zig").HashSetManaged;
const Tracy = @import("../Core/Tracy.zig");

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
        const ECSEventManager = @import("ECSEventManager.zig").ECSEventManager(entity_t);
        const ParentComponent = @import("Components.zig").ParentComponent(entity_t);
        const ChildComponent = @import("Components.zig").ChildComponent(entity_t);

        const Self = @This();

        mComponentsArrays: std.ArrayList(ComponentArray(entity_t)),
        mEntitySkipField: SparseSet(.{
            .SparseT = entity_t,
            .DenseT = entity_t,
            .ValueT = StaticSkipField(components_types.len),
            .value_layout = .InternalArrayOfStructs,
            .allow_resize = .ResizeAllowed,
        }),
        mECSAllocator: std.mem.Allocator,

        pub fn Init(ECSAllocator: std.mem.Allocator, comptime components_list: []const type) !Self {
            var new_component_manager = Self{
                .mComponentsArrays = std.ArrayList(ComponentArray(entity_t)){},
                .mEntitySkipField = try SparseSet(.{
                    .SparseT = entity_t,
                    .DenseT = entity_t,
                    .ValueT = StaticSkipField(components_types.len),
                    .value_layout = .InternalArrayOfStructs,
                    .allow_resize = .ResizeAllowed,
                }).init(ECSAllocator, 20, 10),
                .mECSAllocator = ECSAllocator,
            };

            //add the components for entity hiearchy
            const parent_array = try ComponentArray(entity_t).Init(ECSAllocator, ParentComponent);
            try new_component_manager.mComponentsArrays.append(ECSAllocator, parent_array);

            const child_array = try ComponentArray(entity_t).Init(ECSAllocator, ChildComponent);
            try new_component_manager.mComponentsArrays.append(ECSAllocator, child_array);

            inline for (components_list) |component_type| {
                const new_component_array = try ComponentArray(entity_t).Init(ECSAllocator, component_type);
                try new_component_manager.mComponentsArrays.append(ECSAllocator, new_component_array);
            }

            return new_component_manager;
        }

        pub fn Deinit(self: *Self) void {
            //delete component arrays
            for (self.mComponentsArrays.items) |component_array| {
                component_array.Deinit();
            }

            self.mComponentsArrays.deinit(self.mECSAllocator);
            self.mEntitySkipField.deinit();
        }

        pub fn clearAndFree(self: *Self) void {
            for (self.mComponentsArrays.items) |component_array| {
                component_array.clearAndFree();
            }
            self.mEntitySkipField.clear();
        }

        pub fn CreateEntity(self: *Self, entityID: entity_t) !void {
            std.debug.assert(!self.mEntitySkipField.HasSparse(entityID));
            const dense_ind = self.mEntitySkipField.add(entityID);
            self.mEntitySkipField.getValueByDense(dense_ind).* = StaticSkipField(components_types.len).Init(.AllSkip);
        }

        pub fn DestroyEntity(self: *Self, entity_id: entity_t, ecs_event_manager: ECSEventManager) !void {
            std.debug.assert(self.mEntitySkipField.HasSparse(entity_id));

            // Remove all components from this entity
            const entity_skipfield = self.mEntitySkipField.getValueBySparse(entity_id);

            var field_iter = entity_skipfield.Iterator();
            while (field_iter.Next()) |comp_arr_ind| {
                self.mComponentsArrays.items[comp_arr_ind].DestroyEntity(entity_id, ecs_event_manager);
            }

            // Remove entity from skip field
            _ = self.mEntitySkipField.remove(entity_id);
        }

        pub fn DestroyMultiEntity(self: *Self, entity_id: entity_t) !void {
            std.debug.assert(self.mEntitySkipField.HasSparse(entity_id));

            // Remove all components from this entity
            const entity_skipfield = self.mEntitySkipField.getValueBySparse(entity_id);

            var field_iter = entity_skipfield.Iterator();
            while (field_iter.Next()) |comp_arr_ind| {
                self.mComponentsArrays.items[comp_arr_ind].RemoveComponent(entity_id);
            }

            // Remove entity from skip field
            _ = self.mEntitySkipField.remove(entity_id);
        }

        pub fn DuplicateEntity(self: *Self, original_entity_id: entity_t, new_entity_id: entity_t) void {
            std.debug.assert(self.mEntitySkipField.HasSparse(original_entity_id));
            std.debug.assert(self.mEntitySkipField.HasSparse(new_entity_id));

            const original_skipfield = self.mEntitySkipField.getValueBySparse(original_entity_id);
            const new_skipfield = self.mEntitySkipField.getValueBySparse(new_entity_id);
            @memcpy(&new_skipfield.mSkipField, &original_skipfield.mSkipField);

            var field_iter = original_skipfield.Iterator();
            while (field_iter.Next()) |comp_arr_ind| {
                self.mComponentsArrays.items[comp_arr_ind].DuplicateEntity(original_entity_id, new_entity_id);
            }
        }

        pub fn AddComponent(self: *Self, comptime component_type: type, entityID: entity_t, component: component_type) !*component_type {
            std.debug.assert(@hasDecl(component_type, "Ind"));
            std.debug.assert(self.mEntitySkipField.HasSparse(entityID));
            std.debug.assert(component_type.Ind < self.mComponentsArrays.items.len);
            std.debug.assert(!self.HasComponent(component_type, entityID));

            self.mEntitySkipField.getValueBySparse(entityID).ChangeToUnskipped(component_type.Ind);

            const internal_array_t = InternalComponentArray(entity_t, component_type);
            const internal_array: *internal_array_t = @ptrCast(@alignCast(self.mComponentsArrays.items[component_type.Ind].mPtr));

            return try internal_array.AddComponent(entityID, component);
        }

        pub fn RemoveComponent(self: *Self, entity_id: entity_t, component_ind: usize) !void {
            std.debug.assert(self.mEntitySkipField.HasSparse(entity_id));
            std.debug.assert(component_ind < self.mComponentsArrays.items.len);
            std.debug.assert(self.mComponentsArrays.items[component_ind].HasComponent(entity_id));

            self.mEntitySkipField.getValueBySparse(entity_id).ChangeToSkipped(component_ind);

            try self.mComponentsArrays.items[component_ind].RemoveComponent(entity_id);
        }

        pub fn HasComponent(self: Self, comptime component_type: type, entityID: entity_t) bool {
            std.debug.assert(@hasDecl(component_type, "Ind"));
            std.debug.assert(self.mEntitySkipField.HasSparse(entityID));
            std.debug.assert(component_type.Ind < self.mComponentsArrays.items.len);

            const internal_array_t = InternalComponentArray(entity_t, component_type);
            const internal_array: *internal_array_t = @ptrCast(@alignCast(self.mComponentsArrays.items[component_type.Ind].mPtr));

            return internal_array.HasComponent(entityID);
        }

        pub fn GetComponent(self: Self, comptime component_type: type, entityID: entity_t) ?*component_type {
            std.debug.assert(@hasDecl(component_type, "Ind"));
            std.debug.assert(self.mEntitySkipField.HasSparse(entityID));
            std.debug.assert(component_type.Ind < self.mComponentsArrays.items.len);

            const internal_array_t = InternalComponentArray(entity_t, component_type);
            const internal_array: *internal_array_t = @ptrCast(@alignCast(self.mComponentsArrays.items[component_type.Ind].mPtr));

            return internal_array.GetComponent(entityID);
        }

        pub fn GetMultiData(self: Self, entity_id: entity_t, component_ind: usize) @Vector(4, entity_t) {
            std.debug.assert(self.mEntitySkipField.HasSparse(entity_id));
            std.debug.assert(component_ind < self.mComponentsArrays.items.len);
            std.debug.assert(self.mComponentsArrays.items[component_ind].HasComponent(entity_id));

            return self.mComponentsArrays.items[component_ind].GetMultiData(entity_id);
        }

        pub fn SetMultiData(self: Self, entity_id: entity_t, component_ind: usize, multi_data: @Vector(4, entity_t)) void {
            std.debug.assert(self.mEntitySkipField.HasSparse(entity_id));
            std.debug.assert(component_ind < self.mComponentsArrays.items.len);
            std.debug.assert(self.mComponentsArrays.items[component_ind].HasComponent(entity_id));

            self.mComponentsArrays.items[component_ind].SetMultiData(entity_id, multi_data);
        }

        pub fn GetGroup(self: Self, comptime query: GroupQuery, allocator: std.mem.Allocator) !std.ArrayList(entity_t) {
            switch (query) {
                .Component => |component_type| {
                    std.debug.assert(@hasDecl(component_type, "Ind"));
                    std.debug.assert(component_type.Ind < self.mComponentsArrays.items.len);

                    const internal_array_t = InternalComponentArray(entity_t, component_type);
                    const internal_array: *internal_array_t = @ptrCast(@alignCast(self.mComponentsArrays.items[component_type.Ind].mPtr));

                    return try internal_array.GetAllEntities(allocator);
                },
                .Not => |not| {
                    var result = try self.GetGroup(not.mFirst, allocator);
                    var second = try self.GetGroup(not.mSecond, allocator);
                    defer second.deinit(allocator);
                    try self.EntityListDifference(&result, second, allocator);
                    return result;
                },
                .Or => |ors| {
                    std.debug.assert(ors.len > 0);
                    var result = try self.GetGroup(ors[0], allocator);
                    inline for (ors[1..]) |or_query| {
                        var intermediate = try self.GetGroup(or_query, allocator);
                        defer intermediate.deinit(allocator);
                        try self.EntityListUnion(&result, intermediate, allocator);
                    }
                    return result;
                },
                .And => |ands| {
                    std.debug.assert(ands.len > 0);
                    var result = try self.GetGroup(ands[0], allocator);
                    inline for (ands[1..]) |and_query| {
                        var intermediate = try self.GetGroup(and_query, allocator);
                        defer intermediate.deinit(allocator);
                        try self.EntityListIntersection(&result, intermediate, allocator);
                    }
                    return result;
                },
            }
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
            try result_set.appendSlice(result.items);

            for (list2.items) |entity_id| {
                if (result_set.contains(entity_id) == false) {
                    result.append(allocator, entity_id);
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
