const std = @import("std");
const EntityManager = @import("EntityManager.zig").EntityManager;
const ComponentManager = @import("ComponentManager.zig").ComponentManager;
const GroupQuery = @import("ComponentManager.zig").GroupQuery;
const ArraySet = @import("../Vendor/ziglang-set/src/array_hash_set/managed.zig").ArraySetManaged;
const Tracy = @import("../Core/Tracy.zig");
const EditorWindow = @import("../Imgui/EditorWindow.zig");

pub const ComponentCategory = enum {
    Unique,
    Multiple,
};

pub fn ECSManager(entity_t: type, comptime component_types_size: usize) type {
    return struct {
        const Self = @This();
        mEntityManager: EntityManager(entity_t),
        mComponentManager: ComponentManager(entity_t, component_types_size),
        mECSAllocator: std.mem.Allocator,

        pub fn Init(ECSAllocator: std.mem.Allocator, comptime components_types: []const type) !Self {
            return Self{
                .mEntityManager = EntityManager(entity_t).Init(ECSAllocator),
                .mComponentManager = try ComponentManager(entity_t, component_types_size).Init(ECSAllocator, components_types),
                .mECSAllocator = ECSAllocator,
            };
        }

        pub fn Deinit(self: *Self) void {
            self.mEntityManager.Deinit();
            self.mComponentManager.Deinit();
        }

        pub fn clearAndFree(self: *Self) void {
            self.mEntityManager.clearAndFree();
            self.mComponentManager.clearAndFree();
        }

        //---------------EntityManager--------------
        pub fn CreateEntity(self: *Self) !entity_t {
            const entityID = try self.mEntityManager.CreateEntity();
            try self.mComponentManager.CreateEntity(entityID);
            return entityID;
        }

        pub fn DestroyEntity(self: *Self, entity_id: entity_t) !void {
            //need to change this to handle being able to remove multi components first before destroying the entity.
            //I believe i will need to get the skip field for the given entity
            //then I will need to get the iterator of the skip field (have to make one)
            //then i iterate through the field and call a function GetCategory (have to make)
            //if it is unique then I can call remove component from the component manager
            //if it is multi then i have to get the component, iterate through the linked list
            //destroying each one including the one on the entity to destroy

            try self.mEntityManager.DestroyEntity(entity_id);

            std.debug.assert(self.mComponentManager.mEntitySkipField.HasSparse(entity_id));

            const entity_skipfield = self.mComponentManager.mEntitySkipField.getValueBySparse(entity_id);
            const field_iter = entity_skipfield.Iterator();

            while (field_iter.Next()) |comp_arr_ind| {
                const component_category = self.mComponentManager.mComponentsArrays.items[comp_arr_ind].GetCategory();
                switch (component_category) {
                    .Unique => {
                        self.mComponentManager.mComponentsArrays.items[comp_arr_ind].RemoveComponent(entity_id);
                    },
                    .Multiple => {
                        //remove multi components
                    },
                }
            }

            //try self.mComponentManager.DestroyEntity(entity_id);
        }

        pub fn GetAllEntities(self: Self) ArraySet(entity_t) {
            return self.mEntityManager.GetAllEntities();
        }

        pub fn DuplicateEntity(self: *Self, original_entity_id: entity_t) !entity_t {
            const new_entity_id = try self.CreateEntity();
            self.mComponentManager.DuplicateEntity(original_entity_id, new_entity_id);
            return new_entity_id;
        }

        //for getting groups of entities
        pub fn GetGroup(self: Self, comptime query: GroupQuery, allocator: std.mem.Allocator) !std.ArrayList(entity_t) {
            const zone = Tracy.ZoneInit("ECSM GetGroup", @src());
            defer zone.Deinit();
            return try self.mComponentManager.GetGroup(query, allocator);
        }

        pub fn EntityListDifference(self: Self, result: *std.ArrayList(entity_t), list2: std.ArrayList(entity_t), allocator: std.mem.Allocator) !void {
            try self.mComponentManager.EntityListDifference(result, list2, allocator);
        }

        pub fn EntityListUnion(self: Self, result: *std.ArrayList(entity_t), list2: std.ArrayList(entity_t), allocator: std.mem.Allocator) !void {
            try self.mComponentManager.EntityListUnion(result, list2, allocator);
        }

        pub fn EntityListIntersection(self: Self, result: *std.ArrayList(entity_t), list2: std.ArrayList(entity_t), allocator: std.mem.Allocator) !void {
            try self.mComponentManager.EntityListIntersection(result, list2, allocator);
        }

        //components related functions
        pub fn AddComponent(self: *Self, comptime component_type: type, entity_id: entity_t, new_component: ?component_type) !*component_type {
            const zone = Tracy.ZoneInit("ECSM AddComponent", @src());
            defer zone.Deinit();
            var new_type_component: component_type = if (new_component) |c| c else component_type{};

            switch (component_type.Category) {
                .Unique => {
                    return try self.mComponentManager.AddComponent(component_type, entity_id, new_component);
                },
                .Multiple => {
                    const new_component_entity_id = try self.CreateEntity();

                    if (self.GetComponent(component_type, entity_id)) |component| {
                        //entity already has a component_type

                        const first_component = self.GetComponent(component_type, component.mFirst).?;

                        const last_component = self.GetComponent(component_type, first_component.mPrev).?;

                        //update new components linked list
                        new_type_component.mFirst = first_component.mFirst;
                        new_type_component.mNext = first_component.mFirst;
                        new_type_component.mParent = first_component.mParent;
                        new_type_component.mPrev = first_component.mPrev;

                        //update previous of first one to be this one
                        first_component.mPrev = new_component_entity_id;

                        //update last components next, which is the new one
                        last_component.mNext = new_component_entity_id;

                        return try self.mComponentManager.AddComponent(component_type, new_component_entity_id, new_type_component);
                    } else {
                        var parent_component_type = component_type{};
                        parent_component_type.mFirst = new_component_entity_id;
                        parent_component_type.mNext = new_component_entity_id;
                        parent_component_type.mParent = entity_id;
                        parent_component_type.mPrev = new_component_entity_id;

                        //entity does not have any of this component_type yet so add it directly to the entity
                        new_type_component.mFirst = new_component_entity_id;
                        new_type_component.mNext = new_component_entity_id;
                        new_type_component.mParent = entity_id;
                        new_type_component.mPrev = new_component_entity_id;

                        try self.mComponentManager.AddComponent(component_type, entity_id, parent_component_type);
                        return try self.mComponentManager.AddComponent(component_type, new_component_entity_id, new_type_component);
                    }
                },
            }
        }

        pub fn RemoveComponent(self: *Self, comptime component_type: type, entity_id: entity_t) !void {
            const zone = Tracy.ZoneInit("ECSM RemoveComponent", @src());
            defer zone.Deinit();
            switch (component_type.Category) {
                .Unique => {
                    //in this case the entity ID is just simply the entity we want to remove the component from
                    try self.mComponentManager.RemoveComponent(component_type, entity_id);
                },
                .Multiple => {
                    //entity_id in this case refers to the entity id of the component we want to remove not the parent
                    //multi components always have their own entity_id so we can just ensure linked list pointers are updated
                    //and then remove the entity
                    const remove_component = self.GetComponent(component_type, entity_id).?;
                    const parent_component = self.GetComponent(component_type, remove_component.mParent).?;

                    if (remove_component.mNext == entity_id and remove_component.mPrev == entity_id) {
                        //case: this is the only one of this type of component so we can fully remove from parent
                        try self.mComponentManager.RemoveComponent(component_type, remove_component.mParent);
                    } else {
                        //case: there are multiples of this component
                        const next_component = self.GetComponent(component_type, remove_component.mNext).?;
                        const prev_component = self.GetComponent(component_type, remove_component.mPrev).?;

                        next_component.mPrev = remove_component.mPrev;
                        prev_component.mNext = remove_component.mNext;

                        if (parent_component.mFirst == entity_id) {
                            parent_component.mFirst = remove_component.mNext;
                        }
                    }

                    try self.DestroyEntity(entity_id);
                },
            }
        }

        pub fn HasComponent(self: Self, comptime ComponentType: type, entityID: entity_t) bool {
            const zone = Tracy.ZoneInit("ECSM HasComponent", @src());
            defer zone.Deinit();
            return self.mComponentManager.HasComponent(ComponentType, entityID);
        }

        pub fn GetComponent(self: Self, comptime ComponentType: type, entityID: entity_t) ?*ComponentType {
            const zone = Tracy.ZoneInit("ECSM GetComponent", @src());
            defer zone.Deinit();
            return self.mComponentManager.GetComponent(ComponentType, entityID);
        }
    };
}
