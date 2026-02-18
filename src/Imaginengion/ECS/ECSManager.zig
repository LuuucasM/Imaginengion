const std = @import("std");
const EntityManager = @import("EntityManager.zig").EntityManager;
const ComponentManager = @import("ComponentManager.zig").ComponentManager;
const GroupQuery = @import("ComponentManager.zig").GroupQuery;
const ArraySet = @import("../Vendor/ziglang-set/src/array_hash_set/managed.zig").ArraySetManaged;
const Tracy = @import("../Core/Tracy.zig");
const ECSEventCategory = @import("ECSEvent.zig").ECSEventCategory;
const EngineContext = @import("../Core/EngineContext.zig");

pub const ChildType = enum {
    Entity,
    Script,
};

pub fn ECSManager(entity_t: type, comptime components_types: []const type) type {
    return struct {
        pub const ECSEventManager = @import("ECSEventManager.zig").ECSEventManager(entity_t);
        pub const ParentComponent = @import("Components.zig").ParentComponent(entity_t);
        pub const ChildComponent = @import("Components.zig").ChildComponent(entity_t);

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

        pub fn AddChild(self: *Self, entity_id: entity_t, child_type: ChildType) !entity_t {
            std.debug.assert(self.mEntityManager._IDsInUse.contains(entity_id));

            const zone = Tracy.ZoneInit("ECSM AddChild", @src());
            defer zone.Deinit();

            const new_entity_id = try self.CreateEntity();

            if (self.GetComponent(ParentComponent, entity_id)) |parent_component| {
                const first_child_entity_id = switch (child_type) {
                    .Entity => parent_component.mFirstEntity,
                    .Script => parent_component.mFirstScript,
                };

                if (first_child_entity_id != std.math.maxInt(entity_t)) {
                    const first_child_component = self.GetComponent(ChildComponent, first_child_entity_id).?;

                    const last_child_entity_id = first_child_component.mPrev;
                    const last_child_component = self.GetComponent(ChildComponent, last_child_entity_id).?;

                    const new_child_component = ChildComponent{
                        .mFirst = first_child_entity_id,
                        .mNext = first_child_entity_id,
                        .mParent = entity_id,
                        .mPrev = last_child_entity_id,
                    };

                    _ = try self.AddComponent(new_entity_id, new_child_component);

                    last_child_component.mNext = new_entity_id;

                    first_child_component.mPrev = new_entity_id;
                } else {
                    switch (child_type) {
                        .Entity => parent_component.mFirstEntity = new_entity_id,
                        .Script => parent_component.mFirstScript = new_entity_id,
                    }

                    const new_child_component = ChildComponent{
                        .mFirst = new_entity_id,
                        .mNext = new_entity_id,
                        .mParent = entity_id,
                        .mPrev = new_entity_id,
                    };

                    _ = try self.AddComponent(new_entity_id, new_child_component);
                }
            } else {
                const new_parent_component = switch (child_type) {
                    .Entity => ParentComponent{ .mFirstEntity = new_entity_id },
                    .Script => ParentComponent{ .mFirstScript = new_entity_id },
                };

                _ = try self.AddComponent(entity_id, new_parent_component);

                const new_child_component = ChildComponent{
                    .mFirst = new_entity_id,
                    .mNext = new_entity_id,
                    .mParent = entity_id,
                    .mPrev = new_entity_id,
                };

                _ = try self.AddComponent(new_entity_id, new_child_component);
            }

            return new_entity_id;
        }

        //--------components related functions----------
        pub fn AddComponent(self: *Self, entity_id: entity_t, new_component: anytype) !*@TypeOf(new_component) {
            const zone = Tracy.ZoneInit("ECSM AddComponent", @src());
            defer zone.Deinit();
            const component_t = @TypeOf(new_component);
            _ValidateType(component_t);

            std.debug.assert(self.mEntityManager._IDsInUse.contains(entity_id));

            return try self.mComponentManager.AddComponent(entity_id, new_component);
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
        pub fn ResetComponent(self: *Self, entity_id: entity_t, component: anytype) void {
            const zone = Tracy.ZoneInit("ECSM::ResetComponent", @src());
            defer zone.Deinit();
            const component_t = @typeInfo(component);
            _ValidateType(component_t);

            std.debug.assert(self.mEntityManager._IDsInUse.contains(entity_id));

            self.mComponentManager.ResetComponent(entity_id, component);
        }

        pub fn ProcessEvents(self: *Self, engine_context: *EngineContext, event_category: ECSEventCategory, callback_obj: anytype, callback_fn: fn (@TypeOf(callback_obj), ECSEventManager.ECSEvent) void) !void {
            const zone = Tracy.ZoneInit("ECSM ProcessEvents", @src());
            defer zone.Deinit();
            var iter = self.mECSEventManager.GetEventsIteartor(event_category);
            while (iter.Next()) |event| {
                callback_fn(callback_obj, event);
                switch (event) {
                    .ET_DestroyEntity => |e| {
                        try self._InternalDestroyEntity(engine_context, e.mEntityID);
                    },
                    .ET_RemoveComponent => |e| {
                        try self._InternalRemoveComponent(engine_context, e.mEntityID, e.mComponentInd);
                    },
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
            try self.mComponentManager.RemoveComponent(engine_context, entity_id, component_ind);
        }

        fn _InternalDestroyEntity(self: *Self, engine_context: *EngineContext, entity_id: entity_t) !void {
            std.debug.assert(self.mEntityManager._IDsInUse.contains(entity_id));
            const zone = Tracy.ZoneInit("ECSM Internal Destroy Entity", @src());
            defer zone.Deinit();
            try self._InternalRemoveFromHierarchy(engine_context, entity_id);
            try self._InternalRemoveScripts(engine_context, entity_id);
            try self.mEntityManager.DestroyEntity(engine_context.EngineAllocator(), entity_id);
            try self.mComponentManager.DestroyEntity(engine_context, entity_id);
        }

        fn _InternalRemoveFromHierarchy(self: *Self, engine_context: *EngineContext, entity_id: entity_t) anyerror!void {
            std.debug.assert(self.mEntityManager._IDsInUse.contains(entity_id));
            const zone = Tracy.ZoneInit("ECSM Internal Remove From Hierarchy", @src());
            defer zone.Deinit();

            //delete all children
            if (self.GetComponent(ParentComponent, entity_id)) |parent_component| {
                if (parent_component.mFirstEntity != std.math.maxInt(entity_t)) {
                    var curr_id = parent_component.mFirstEntity;
                    var curr_component = self.GetComponent(ChildComponent, curr_id).?;

                    while (true) : (if (curr_id == parent_component.mFirstEntity) break) {
                        const next_id = curr_component.mNext;
                        try self._InternalDestroyEntity(engine_context, curr_id);

                        curr_id = next_id;
                        curr_component = self.GetComponent(ChildComponent, curr_id).?;
                    }
                }
            }

            //remove from child hierarchy if we are in one
            if (self.GetComponent(ChildComponent, entity_id)) |child_component| {
                const parent_entity: entity_t = child_component.mParent;
                if (self.GetComponent(ParentComponent, parent_entity)) |parent_component| {
                    // If this is the only child see if theres any scripts and remove / invalidate depending
                    if (child_component.mNext == entity_id and child_component.mPrev == entity_id) {
                        if (parent_component.mFirstScript == std.math.maxInt(entity_t)) {
                            try self.RemoveComponent(engine_context.EngineAllocator(), ParentComponent, parent_entity);
                        } else {
                            parent_component.mFirstEntity = std.math.maxInt(entity_t);
                        }
                    } else {
                        // Relink siblings around this child
                        const next_comp = self.GetComponent(ChildComponent, child_component.mNext).?;
                        const prev_comp = self.GetComponent(ChildComponent, child_component.mPrev).?;
                        next_comp.mPrev = child_component.mPrev;
                        prev_comp.mNext = child_component.mNext;
                        // If this child was the first, move first to next
                        if (parent_component.mFirstEntity == entity_id) {
                            parent_component.mFirstEntity = child_component.mNext;
                        }
                    }
                }
            }
        }

        fn _InternalRemoveScripts(self: *Self, engine_context: *EngineContext, entity_id: entity_t) anyerror!void {
            if (self.GetComponent(ParentComponent, entity_id)) |parent_component| {
                if (parent_component.mFirstScript == std.math.maxInt(entity_t)) return;

                var curr_id = parent_component.mFirstScript;
                var curr_component = self.GetComponent(ChildComponent, curr_id).?;

                while (true) : (if (curr_id == parent_component.mFirstEntity) break) {
                    const next_id = curr_component.mNext;
                    try self._InternalDestroyEntity(engine_context, curr_id);

                    curr_id = next_id;
                    curr_component = self.GetComponent(ChildComponent, curr_id).?;
                }
            }
        }

        fn _ValidateCompList(comptime component_list: []const type) void {
            inline for (component_list) |component_type| {
                const type_name = std.fmt.comptimePrint(" {s}\n", .{@typeName(component_type)});
                const type_info = @typeInfo(component_type);
                switch (type_info) {
                    .@"struct" => {},
                    else => @compileError(type_name ++ "component must be a struct!"),
                }

                if (!@hasDecl(component_type, "Name")) {
                    @compileError(type_name ++ "Type needs 'Name' pub const declaration ");
                }
                if (!@hasDecl(component_type, "Ind")) {
                    @compileError(type_name ++ "Type needs 'Ind' pub const declaration ");
                }
                if (!std.meta.hasFn(component_type, "Deinit")) {
                    @compileError(type_name ++ "Type needs 'Deinit' member function ");
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

            const type_info = @typeInfo(component_type);
            if (type_info != .@"struct") {
                @compileError(type_name ++ "must be of type struct");
            }

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
                @compileError(type_name ++ " can not be used with this ECS");
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
                    if (ors.len < 1) {
                        @compileError("Must have 1 or more in ors group");
                    }
                    inline for (ors[1..]) |or_query| {
                        _ValidateGroupQuery(or_query);
                    }
                },
                .And => |ands| {
                    if (ands.len < 1) {
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
