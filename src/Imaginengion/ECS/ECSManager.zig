const std = @import("std");
const EntityManager = @import("EntityManager.zig").EntityManager;
const ComponentManager = @import("ComponentManager.zig").ComponentManager;
const GroupQuery = @import("ComponentManager.zig").GroupQuery;
const ArraySet = @import("../Vendor/ziglang-set/src/array_hash_set/managed.zig").ArraySetManaged;
const Tracy = @import("../Core/Tracy.zig");
const ECSEventCategory = @import("ECSEvent.zig").ECSEventCategory;
const EngineContext = @import("../Core/EngineContext.zig");

pub const ComponentCategory = enum {
    Unique,
    Multiple,
};

pub fn ECSManager(entity_t: type, comptime components_types: []const type) type {
    return struct {
        const ECSEventManager = @import("ECSEventManager.zig").ECSEventManager(entity_t);
        const ParentComponent = @import("Components.zig").ParentComponent(entity_t);
        const ChildComponent = @import("Components.zig").ChildComponent(entity_t);

        const Self = @This();
        mEntityManager: EntityManager(entity_t) = .{},
        mComponentManager: ComponentManager(entity_t, components_types) = .{},
        mECSEventManager: ECSEventManager = .{},

        pub fn Init(self: *Self, engine_allocator: std.mem.Allocator) !void {
            _ValidateCompList(components_types);
            const zone = Tracy.ZoneInit("ECSM Init", @src());
            defer zone.Deinit();

            self.mEntityManager.Init(engine_allocator);
            try self.mComponentManager.Init(engine_allocator);
            try self.mECSEventManager.Init();
        }

        pub fn Deinit(self: *Self, engine_context: *EngineContext) !void {
            const zone = Tracy.ZoneInit("ECSM Deinit", @src());
            defer zone.Deinit();
            self.mEntityManager.Deinit(engine_context.EngineAllocator());
            try self.mComponentManager.Deinit(engine_context);
            self.mECSEventManager.Deinit(engine_context.EngineAllocator());
        }

        pub fn clearAndFree(self: *Self, engine_context: *EngineContext) void {
            const zone = Tracy.ZoneInit("ECSM clearAndFree", @src());
            defer zone.Deinit();
            self.mEntityManager.clearAndFree(engine_context.EngineAllocator());
            self.mComponentManager.clearAndFree(engine_context);
        }

        //---------------EntityManager--------------
        pub fn CreateEntity(self: *Self) !entity_t {
            const zone = Tracy.ZoneInit("ECSM CreateEntity", @src());
            defer zone.Deinit();
            const entityID = try self.mEntityManager.CreateEntity();
            try self.mComponentManager.CreateEntity(entityID);
            return entityID;
        }

        pub fn DestroyEntity(self: *Self, engine_allocator: std.mem.Allocator, entity_id: entity_t) !void {
            std.debug.assert(self.mEntityManager._IDsInUse.contains(entity_id));
            const zone = Tracy.ZoneInit("ECSM DestroyEntity", @src());
            defer zone.Deinit();
            try self.mECSEventManager.Insert(engine_allocator, .{ .ET_DestroyEntity = .{ .mEntityID = entity_id } });
        }

        pub fn GetAllEntities(self: Self) ArraySet(entity_t) {
            const zone = Tracy.ZoneInit("ECSM GetAllEntities", @src());
            defer zone.Deinit();
            return self.mEntityManager.GetAllEntities();
        }

        pub fn DuplicateEntity(self: *Self, original_entity_id: entity_t) !entity_t {
            std.debug.assert(self.mEntityManager._IDsInUse.contains(original_entity_id));
            const zone = Tracy.ZoneInit("ECSM DuplicateEntity", @src());
            defer zone.Deinit();
            const new_entity_id = try self.CreateEntity();
            self.mComponentManager.DuplicateEntity(original_entity_id, new_entity_id);
            return new_entity_id;
        }

        pub fn IsActiveEntityID(self: *Self, entity_id: entity_t) bool {
            return self.mEntityManager._IDsInUse.contains(entity_id);
        }

        //for getting groups of entities
        pub fn GetGroup(self: Self, allocator: std.mem.Allocator, comptime query: GroupQuery) !std.ArrayList(entity_t) {
            _ValidateGroupQuery(query);
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

        pub fn AddChild(self: *Self, entity_id: entity_t) !entity_t {
            std.debug.assert(self.mEntityManager._IDsInUse.contains(entity_id));

            const zone = Tracy.ZoneInit("ECSM AddChild", @src());
            defer zone.Deinit();

            const new_entity_id = try self.CreateEntity();

            if (self.GetComponent(ParentComponent, entity_id)) |parent_component| {
                const first_child_entity_id = parent_component.mFirstChild;
                const first_child_component = self.GetComponent(ChildComponent, first_child_entity_id).?;

                const last_child_entity_id = first_child_component.mPrev;
                const last_child_component = self.GetComponent(ChildComponent, last_child_entity_id).?;

                const new_child_component = ChildComponent{
                    .mFirst = first_child_entity_id,
                    .mNext = first_child_entity_id,
                    .mParent = entity_id,
                    .mPrev = last_child_entity_id,
                };

                _ = try self.AddComponent(ChildComponent, new_entity_id, new_child_component);

                last_child_component.mNext = new_entity_id;

                first_child_component.mPrev = new_entity_id;
            } else {
                const new_parent_component = ParentComponent{ .mFirstChild = new_entity_id };
                _ = try self.AddComponent(ParentComponent, entity_id, new_parent_component);

                const new_child_component = ChildComponent{
                    .mFirst = new_entity_id,
                    .mNext = new_entity_id,
                    .mParent = entity_id,
                    .mPrev = new_entity_id,
                };

                _ = try self.AddComponent(ChildComponent, new_entity_id, new_child_component);
            }

            return new_entity_id;
        }

        //--------components related functions----------
        pub fn AddComponent(self: *Self, comptime component_type: type, entity_id: entity_t, new_component: ?component_type) !*component_type {
            _ValidateType(component_type);
            std.debug.assert(self.mEntityManager._IDsInUse.contains(entity_id));
            const zone = Tracy.ZoneInit("ECSM AddComponent", @src());
            defer zone.Deinit();

            var new_type_component: component_type = if (new_component) |c| c else component_type{};

            switch (component_type.Category) {
                .Unique => {
                    return try self.mComponentManager.AddComponent(component_type, entity_id, new_type_component);
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

                        _ = try self.mComponentManager.AddComponent(component_type, entity_id, parent_component_type);
                        return try self.mComponentManager.AddComponent(component_type, new_component_entity_id, new_type_component);
                    }
                },
            }
        }
        pub fn RemoveComponent(self: *Self, engine_allocator: std.mem.Allocator, comptime component_type: type, entity_id: entity_t) !void {
            _ValidateType(component_type);
            std.debug.assert(self.mEntityManager._IDsInUse.contains(entity_id));
            const zone = Tracy.ZoneInit("ECSM RemoveComponent", @src());
            defer zone.Deinit();
            try self.mECSEventManager.Insert(engine_allocator, .{ .ET_RemoveComponent = .{ .mEntityID = entity_id, .mComponentInd = component_type.Ind } });
        }
        pub fn RemoveComponentInd(self: *Self, engine_allocator: std.mem.Allocator, entity_id: entity_t, component_ind: usize) !void {
            std.debug.assert(self.mEntityManager._IDsInUse.contains(entity_id));
            std.debug.assert(self.mComponentManager.mComponentsArrays.items.len > component_ind);
            const zone = Tracy.ZoneInit("ECSM RemoveComponentInd", @src());
            defer zone.Deinit();
            try self.mECSEventManager.Insert(engine_allocator, .{ .ET_RemoveComponent = .{ .mEntityID = entity_id, .mComponentInd = component_ind } });
        }

        pub fn HasComponent(self: Self, comptime ComponentType: type, entity_id: entity_t) bool {
            std.debug.assert(self.mEntityManager._IDsInUse.contains(entity_id));
            const zone = Tracy.ZoneInit("ECSM HasComponent", @src());
            defer zone.Deinit();
            return self.mComponentManager.HasComponent(ComponentType, entity_id);
        }

        pub fn GetComponent(self: Self, comptime component_type: type, entity_id: entity_t) ?*component_type {
            _ValidateType(component_type);
            std.debug.assert(self.mEntityManager._IDsInUse.contains(entity_id));

            const zone = Tracy.ZoneInit("ECSM GetComponent", @src());
            defer zone.Deinit();
            return self.mComponentManager.GetComponent(component_type, entity_id);
        }

        pub fn ProcessEvents(self: *Self, engine_context: *EngineContext, event_category: ECSEventCategory) !void {
            const zone = Tracy.ZoneInit("ECSM ProcessEvents", @src());
            defer zone.Deinit();
            var iter = self.mECSEventManager.GetEventsIteartor(event_category);
            while (iter.Next()) |event| {
                switch (event) {
                    .ET_DestroyEntity => |e| try self._InternalDestroyEntity(engine_context, e.mEntityID),
                    .ET_CleanMultiEntity => |e| try self._InternalDestroyMultiEntity(engine_context, e.mEntityID),
                    .ET_RemoveComponent => |e| try self._InternalRemoveComponent(engine_context, e.mEntityID, e.mComponentInd),
                    else => {
                        @panic("Default Events are not allowed!\n");
                    },
                }
            }
            self.mECSEventManager.ClearEvents(engine_context.EngineAllocator(), event_category);
        }

        fn _InternalRemoveComponent(self: *Self, engine_context: *EngineContext, entity_id: entity_t, component_ind: usize) !void {
            std.debug.assert(self.mEntityManager._IDsInUse.contains(entity_id));
            std.debug.assert(self.mComponentManager.mComponentsArrays.items.len > component_ind);
            const zone = Tracy.ZoneInit("ECSM Internal Remove Component", @src());
            defer zone.Deinit();
            const component_category = self.mComponentManager.mComponentsArrays.items[component_ind].GetCategory();
            switch (component_category) {
                .Unique => {
                    //in this case the entity ID is just simply the entity we want to remove the component from
                    try self.mComponentManager.RemoveComponent(engine_context, entity_id, component_ind);
                },
                .Multiple => {
                    //entity_id in this case refers to the entity id of the component we want to remove not the parent
                    //multi components always have their own entity_id so we can just ensure linked list pointers are updated
                    //and then destroy the entity
                    //0 -> mParent, 1 -> mFirst, 2 -> mNext, 3 -> mPrev
                    const removed_multidata = self.mComponentManager.GetMultiData(entity_id, component_ind);
                    var parent_multidata = self.mComponentManager.GetMultiData(removed_multidata[0], component_ind);

                    if (removed_multidata[2] == entity_id and removed_multidata[3] == entity_id) {
                        //case: this is the only one of this type of component so we can fully remove from parent
                        try self.mComponentManager.RemoveComponent(engine_context, removed_multidata[0], component_ind);
                    } else {
                        //case: there are multiples of this component
                        var next_multidata = self.mComponentManager.GetMultiData(removed_multidata[2], component_ind);
                        var prev_multidata = self.mComponentManager.GetMultiData(removed_multidata[3], component_ind);

                        next_multidata[3] = removed_multidata[3];
                        prev_multidata[2] = removed_multidata[2];

                        self.mComponentManager.SetMultiData(removed_multidata[2], component_ind, next_multidata);
                        self.mComponentManager.SetMultiData(removed_multidata[3], component_ind, prev_multidata);

                        if (parent_multidata[1] == entity_id) {
                            parent_multidata[1] = removed_multidata[2];
                            self.mComponentManager.SetMultiData(removed_multidata[0], component_ind, parent_multidata);
                        }
                    }

                    try self._InternalDestroyMultiEntity(engine_context, entity_id);
                },
            }
        }

        fn _InternalDestroyEntity(self: *Self, engine_context: *EngineContext, entity_id: entity_t) !void {
            std.debug.assert(self.mEntityManager._IDsInUse.contains(entity_id));
            const zone = Tracy.ZoneInit("ECSM Internal Destroy Entity", @src());
            defer zone.Deinit();
            try self._InternalRemoveFromHierarchy(engine_context, entity_id);
            try self.mEntityManager.DestroyEntity(engine_context.EngineAllocator(), entity_id);
            try self.mComponentManager.DestroyEntity(engine_context, entity_id, &self.mECSEventManager);
        }

        fn _InternalDestroyMultiEntity(self: *Self, engine_context: *EngineContext, entity_id: entity_t) !void {
            std.debug.assert(self.mEntityManager._IDsInUse.contains(entity_id));
            const zone = Tracy.ZoneInit("ECSM Internal Destroy MultiEntity", @src());
            defer zone.Deinit();
            try self._InternalRemoveFromHierarchy(engine_context, entity_id);
            try self.mEntityManager.DestroyEntity(engine_context.EngineAllocator(), entity_id);
            try self.mComponentManager.DestroyMultiEntity(engine_context, entity_id);
        }

        fn _InternalRemoveFromHierarchy(self: *Self, engine_context: *EngineContext, entity_id: entity_t) anyerror!void {
            std.debug.assert(self.mEntityManager._IDsInUse.contains(entity_id));
            const zone = Tracy.ZoneInit("ECSM Internal Remove From Hierarchy", @src());
            defer zone.Deinit();
            //delete all children
            if (self.GetComponent(ParentComponent, entity_id)) |parent_component| {
                var curr_id = parent_component.mFirstChild;
                var curr_component = self.GetComponent(ChildComponent, curr_id).?;

                while (true) : (if (curr_id == parent_component.mFirstChild) break) {
                    const next_id = curr_component.mNext;
                    try self._InternalDestroyEntity(engine_context, curr_id);

                    curr_id = next_id;
                    curr_component = self.GetComponent(ChildComponent, curr_id).?;
                }
            }

            //remove from child hierarchy if we are in one
            if (self.GetComponent(ChildComponent, entity_id)) |child_component| {
                const parent_entity: entity_t = child_component.mParent;
                if (self.GetComponent(ParentComponent, parent_entity)) |parent_component| {
                    // If this is the only child, remove the ParentComponent from the parent
                    if (child_component.mNext == entity_id and child_component.mPrev == entity_id) {
                        try self.RemoveComponent(engine_context.EngineAllocator(), ParentComponent, parent_entity);
                    } else {
                        // Relink siblings around this child
                        const next_comp = self.GetComponent(ChildComponent, child_component.mNext).?;
                        const prev_comp = self.GetComponent(ChildComponent, child_component.mPrev).?;
                        next_comp.mPrev = child_component.mPrev;
                        prev_comp.mNext = child_component.mNext;
                        // If this child was the first, move first to next
                        if (parent_component.mFirstChild == entity_id) {
                            parent_component.mFirstChild = child_component.mNext;
                        }
                    }
                }
            }
        }

        fn _ValidateCompList(comptime component_list: []const type) void {
            inline for (component_list) |component_type| {
                const type_name = std.fmt.comptimePrint(" {s}\n", .{@typeName(component_type)});

                if (!@hasDecl(component_type, "Category")) {
                    @compileError("Type needs 'Category' pub const declaration " ++ type_name);
                }
                if (!@hasDecl(component_type, "Name")) {
                    @compileError("Type needs 'Name' pub const declaration " ++ type_name);
                }
                if (!@hasDecl(component_type, "Ind")) {
                    @compileError("Type needs 'Ind' pub const declaration " ++ type_name);
                }
                if (!std.meta.hasFn(component_type, "Deinit")) {
                    @compileError("Type needs 'Deinit' member function " ++ type_name);
                }

                if (component_type.Category == .Multiple) {
                    if (!@hasField(component_type, "mParent")) {
                        @compileError("Type needs 'mParent' member variable because component Category is multiple " ++ type_name);
                    }
                    if (!@hasField(component_type, "mFirst")) {
                        @compileError("Type needs 'mFirst' member varaible because component Category is multiple " ++ type_name);
                    }
                    if (!@hasField(component_type, "mPrev")) {
                        @compileError("Type needs 'mPrev' member variable because component Category is multiple " ++ type_name);
                    }
                    if (!@hasField(component_type, "mNext")) {
                        @compileError("Type needs 'mNext' member variable because component Category is multiple " ++ type_name);
                    }
                }

                { //checking the deinit function for correctness
                    const deinit_info = @typeInfo(@TypeOf(component_type.Deinit));
                    if (deinit_info != .@"fn") {
                        @compileError(type_name ++ "'s Deinit must be a function ");
                    }

                    const fn_info = deinit_info.@"fn";
                    if (fn_info.params.len != 2) {
                        @compileError(type_name ++ "'s Deinit must have 2 parameters");
                    }

                    const first_param = fn_info.params[0].type.?;
                    if (first_param != *component_type) {
                        @compileError(type_name ++ "'s Deinit's first parameter must be *type right now it is " ++ @typeName(first_param));
                    }

                    const second_param = fn_info.params[1].type.?;
                    if (second_param != *EngineContext) {
                        @compileError(type_name ++ "'s Deinit's second parameter must be *EngineContext currently " ++ @typeName(second_param));
                    }

                    const return_type = fn_info.return_type.?;
                    const return_type_info = @typeInfo(return_type);

                    if (return_type_info != .error_union) {
                        @compileError(type_name ++ "'s Deinit's return type must be error union");
                    }

                    const payload_type = return_type_info.error_union.payload;
                    if (payload_type != void) {
                        @compileError(type_name ++ "'s Deinit's return payload must be void, currently " ++ @typeName(payload_type));
                    }
                }
            }
        }

        fn _ValidateType(comptime component_type: type) void {
            const type_name = std.fmt.comptimePrint(" {s}\n", .{@typeName(component_type)});
            comptime var is_valid_type: bool = false;
            inline for (components_types) |comp_t| {
                if (component_type == comp_t) {
                    is_valid_type = true;
                }
            }
            if (component_type == ParentComponent or component_type == ChildComponent) {
                is_valid_type = true;
            }
            if (is_valid_type == false) {
                @compileError("that type can not be used with this ECS" ++ type_name);
            }
        }

        fn _ValidateGroupQuery(comptime query: GroupQuery) void {
            switch (query) {
                .Component => |component_type| {
                    _ValidateType(component_type);
                },
                .Not => |not| {
                    _ValidateGroupQuery(not.mFirst);
                    _ValidateGroupQuery(not.mSecond);
                },
                .Or => |ors| {
                    if (ors.len == 0) {
                        @compileError("Must have 1 or more in ors group");
                    }
                    inline for (ors[1..]) |or_query| {
                        _ValidateGroupQuery(or_query);
                    }
                },
                .And => |ands| {
                    if (ands.len == 0) {
                        @compileError("Must have 1 or more in ands group");
                    }
                    inline for (ands[1..]) |and_query| {
                        _ValidateGroupQuery(and_query);
                    }
                },
            }
        }
    };
}
