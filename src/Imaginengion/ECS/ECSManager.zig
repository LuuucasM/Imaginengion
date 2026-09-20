const std = @import("std");
const ComponentManager = @import("ComponentManager.zig").ComponentManager;
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const ECSEventData = @import("../Events/ECSEventData.zig");
const EventManager = @import("../Events/EventManager.zig");
pub const BuiltinComponentCount = @import("Components.zig").BuiltinComponentCount;
pub const MainObjectComponent = @import("Components.zig").MainObjectComponent;
pub const EntityTagComponent = @import("Components.zig").EntityTagComponent;
pub const ScriptTagComponent = @import("Components.zig").ScriptTagComponent;

pub const ChildType = enum {
    Entity,
    Script,
};

pub const GroupQuery = union(enum) {
    And: []const GroupQuery,
    Or: []const GroupQuery,
    Not: struct {
        mFirst: *const GroupQuery,
        mSecond: *const GroupQuery,
    },
    Component: type,
};

pub fn ECSManager(entity_t: type, comptime components_types: []const type) type {
    return struct {
        // ECSEventData's events are generic over the id type, so bind them here before handing the pair to EventManager
        pub const ECSEventDataT = struct {
            pub const EventCategories = ECSEventData.EventCategories;
            pub const EventT = ECSEventData.EventT(entity_t);
        };
        pub const ECSEventManager = EventManager.EventManager(ECSEventDataT);
        pub const ParentComponent = @import("Components.zig").ParentComponent(entity_t);
        pub const ChildComponent = @import("Components.zig").ChildComponent(entity_t);
        pub const SkipFieldComponent = @import("Components.zig").SkipFieldComponent(components_types.len);
        pub const ComponentManagerT = ComponentManager(entity_t, components_types);
        pub const ECSCallbackList = ECSEventManager.CallbackList;
        pub const ECSEventCallback = ECSEventManager.EventCallback;
        const Self = @This();

        pub const empty: Self = .{
            .mNextID = 0,
            .mComponentManager = .empty,
            .mECSEventManager = .empty,
        };

        mNextID: entity_t = 0,
        mComponentManager: ComponentManagerT,
        mECSEventManager: ECSEventManager,

        pub fn Init(self: *Self, engine_allocator: std.mem.Allocator) !void {
            _ValidateCompList(components_types);
            const zone = Tracy.ZoneInit("ECSM Init", @src());
            defer zone.Deinit();
            try self.mComponentManager.Init(engine_allocator);
        }

        pub fn Deinit(self: *Self, engine_context: *EngineContext) !void {
            const zone = Tracy.ZoneInit("ECSM Deinit", @src());
            defer zone.Deinit();
            try self.mComponentManager.Deinit(engine_context);
            self.mECSEventManager.Deinit(engine_context.EngineAllocator());
        }

        pub fn clearAndFree(self: *Self, engine_context: *EngineContext) !void {
            const zone = Tracy.ZoneInit("ECSM clearAndFree", @src());
            defer zone.Deinit();
            try self.mComponentManager.clearAndFree(engine_context);
            // pending events refer to entities that no longer exist
            self.mECSEventManager.EventsReset(engine_context.EngineAllocator(), .ClearAndFree);
            self.mNextID = 0;
        }

        /// Deep copies this ECS into `other`, which must be initialized and empty.
        /// Every entity keeps its id, generation included, so ids held outside the ECS still point at
        /// the right entity in the copy: the manager's UUID map, and components naming objects that
        /// live in another manager of the same world.
        pub fn Copy(self: *Self, engine_context: *EngineContext, other: *Self) !void {
            const zone = Tracy.ZoneInit("ECSM Copy", @src());
            defer zone.Deinit();

            std.debug.assert(other.mNextID == 0);

            try self.mComponentManager.CopyInto(engine_context, &other.mComponentManager);
            errdefer other.mComponentManager.clearAndFree(engine_context) catch {};

            // queued events name entities by id, which the copy shares, so they carry over as they are
            try self.mECSEventManager.CopyInto(engine_context.EngineAllocator(), &other.mECSEventManager);

            other.mNextID = self.mNextID;
        }

        //---------------entity lifetime--------------
        pub fn CreateEntity(self: *Self, engine_allocator: std.mem.Allocator) !entity_t {
            const zone = Tracy.ZoneInit("ECSM CreateEntity", @src());
            defer zone.Deinit();

            const new_entity_id = try self._CreateID(engine_allocator);
            _ = try self.mComponentManager.AddComponent(engine_allocator, new_entity_id, EntityTagComponent{});

            return new_entity_id;
        }

        fn CreateScript(self: *Self, engine_allocator: std.mem.Allocator) !entity_t {
            const zone = Tracy.ZoneInit("ECSM CreateScript", @src());
            defer zone.Deinit();

            const new_entity_id = try self._CreateID(engine_allocator);
            _ = try self.mComponentManager.AddComponent(engine_allocator, new_entity_id, ScriptTagComponent{});

            return new_entity_id;
        }

        // returns an active id that has only its SkipFieldComponent, reusing a destroyed id when there is one
        fn _CreateID(self: *Self, engine_allocator: std.mem.Allocator) !entity_t {
            if (self.mComponentManager.ReuseFreeEntity()) |reused_id| return reused_id;

            const new_entity_id = self.mNextID;
            std.debug.assert(!self.IsActiveEntity(new_entity_id));

            try self.mComponentManager.CreateNewEntity(engine_allocator, new_entity_id);
            self.mNextID += 1; // only consume the id once it has actually been created

            return new_entity_id;
        }

        /// Queues the destroy. The entity and its children stay alive until ProcessEvents runs.
        pub fn DestroyEntity(self: *Self, engine_context: *EngineContext, entity_id: entity_t) !void {
            std.debug.assert(self.IsActiveEntity(entity_id));
            const zone = Tracy.ZoneInit("ECSM DestroyEntity", @src());
            defer zone.Deinit();

            try self.mECSEventManager.Insert(engine_context.EngineAllocator(), .EndOfFrame, .{ .DestroyEntity = .{ .mEntityID = entity_id } });
        }

        /// Every active entity, because they all carry a SkipFieldComponent.
        pub fn GetAllEntities(self: Self, allocator: std.mem.Allocator) !std.ArrayList(entity_t) {
            const zone = Tracy.ZoneInit("ECSM GetAllEntities", @src());
            defer zone.Deinit();
            return try self.GetGroup(allocator, .{ .Component = SkipFieldComponent });
        }

        /// Copies an entity along with its children and scripts.
        /// The copy joins the original's parent as another child, or becomes a root when the original is one.
        pub fn DuplicateEntity(self: *Self, engine_context: *EngineContext, original_entity_id: entity_t) !entity_t {
            std.debug.assert(self.IsActiveEntity(original_entity_id));
            const zone = Tracy.ZoneInit("ECSM DuplicateEntity", @src());
            defer zone.Deinit();

            const engine_allocator = engine_context.EngineAllocator();
            const child_type: ChildType = if (self.HasComponent(ScriptTagComponent, original_entity_id)) .Script else .Entity;

            const new_entity_id = if (self.GetComponent(ChildComponent, original_entity_id)) |child_component|
                try self.AddChild(engine_allocator, child_component.mParent, child_type)
            else switch (child_type) {
                .Entity => try self.CreateEntity(engine_allocator),
                .Script => try self.CreateScript(engine_allocator),
            };

            try self._InternalDuplicateInto(engine_context, original_entity_id, new_entity_id);

            return new_entity_id;
        }

        // copies one entity's components and subtree onto another, already created, entity
        fn _InternalDuplicateInto(self: *Self, engine_context: *EngineContext, original_entity_id: entity_t, new_entity_id: entity_t) anyerror!void {
            try self.mComponentManager.DuplicateEntity(engine_context, original_entity_id, new_entity_id);

            try self._InternalDuplicateChildren(engine_context, original_entity_id, new_entity_id, .Entity);
            try self._InternalDuplicateChildren(engine_context, original_entity_id, new_entity_id, .Script);
        }

        fn _InternalDuplicateChildren(self: *Self, engine_context: *EngineContext, original_entity_id: entity_t, new_entity_id: entity_t, child_type: ChildType) anyerror!void {
            const first_id = blk: {
                // only the id is kept: AddChild below moves the ParentComponent array
                const parent_component = self.GetComponent(ParentComponent, original_entity_id) orelse return;
                break :blk switch (child_type) {
                    .Entity => parent_component.mFirstEntity,
                    .Script => parent_component.mFirstScript,
                };
            };
            if (first_id == std.math.maxInt(entity_t)) return;

            var curr_id = first_id;
            while (true) {
                const next_id = self.GetComponent(ChildComponent, curr_id).?.mNext;

                const new_child_id = try self.AddChild(engine_context.EngineAllocator(), new_entity_id, child_type);
                try self._InternalDuplicateInto(engine_context, curr_id, new_child_id);

                if (next_id == first_id) break; // the list is circular
                curr_id = next_id;
            }
        }

        pub fn IsActiveEntity(self: Self, entity_id: entity_t) bool {
            return self.mComponentManager.IsActiveEntity(entity_id);
        }

        pub fn GetGroupMask(comptime query: GroupQuery) SkipFieldComponent.StaticSkipFieldT {
            _ValidateGroupQuery(query);
            return ComponentManagerT.GetGroupMask(query);
        }

        //for getting groups of entities
        pub fn GetGroup(self: Self, allocator: std.mem.Allocator, comptime query: GroupQuery) !std.ArrayList(entity_t) {
            _ValidateGroupQuery(query);
            const zone = Tracy.ZoneInit("ECSM GetGroup", @src());
            defer zone.Deinit();

            const mask = comptime ComponentManagerT.GetGroupMask(query);
            return try self.mComponentManager.GetGroup(query, &mask, allocator);
        }

        pub fn EntityListMask(self: Self, result: *std.ArrayList(entity_t), mask: *const SkipFieldComponent.StaticSkipFieldT, allocator: std.mem.Allocator) !void {
            try self.mComponentManager.EntityListMask(result, mask, allocator);
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

        pub fn AddChild(self: *Self, engine_allocator: std.mem.Allocator, entity_id: entity_t, child_type: ChildType) !entity_t {
            std.debug.assert(self.IsActiveEntity(entity_id));

            const zone = Tracy.ZoneInit("ECSM AddChild", @src());
            defer zone.Deinit();

            const new_entity_id = switch (child_type) {
                .Entity => try self.CreateEntity(engine_allocator),
                .Script => try self.CreateScript(engine_allocator),
            };

            if (self.GetComponent(ParentComponent, entity_id)) |parent_component| {
                const first_child_entity_id = switch (child_type) {
                    .Entity => parent_component.mFirstEntity,
                    .Script => parent_component.mFirstScript,
                };

                if (first_child_entity_id != std.math.maxInt(entity_t)) {
                    const last_child_entity_id = self.GetComponent(ChildComponent, first_child_entity_id).?.mPrev;

                    const new_child_component = ChildComponent{
                        .mFirst = first_child_entity_id,
                        .mNext = first_child_entity_id,
                        .mParent = entity_id,
                        .mPrev = last_child_entity_id,
                    };

                    // add before touching the siblings: this grows the ChildComponent array,
                    // which moves every component already in it
                    _ = try self.AddComponent(engine_allocator, new_entity_id, new_child_component);

                    // both are the same component when the parent only had one child, which is still correct
                    const first_child_component = self.GetComponent(ChildComponent, first_child_entity_id).?;
                    const last_child_component = self.GetComponent(ChildComponent, last_child_entity_id).?;

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

                    _ = try self.AddComponent(engine_allocator, new_entity_id, new_child_component);
                }
            } else {
                const new_parent_component = switch (child_type) {
                    .Entity => ParentComponent{ .mFirstEntity = new_entity_id },
                    .Script => ParentComponent{ .mFirstScript = new_entity_id },
                };

                _ = try self.AddComponent(engine_allocator, entity_id, new_parent_component);

                const new_child_component = ChildComponent{
                    .mFirst = new_entity_id,
                    .mNext = new_entity_id,
                    .mParent = entity_id,
                    .mPrev = new_entity_id,
                };

                _ = try self.AddComponent(engine_allocator, new_entity_id, new_child_component);
            }

            return new_entity_id;
        }

        //--------components related functions----------
        pub fn AddComponent(self: *Self, engine_allocator: std.mem.Allocator, entity_id: entity_t, new_component: anytype) !*@TypeOf(new_component) {
            const zone = Tracy.ZoneInit("ECSM AddComponent", @src());
            defer zone.Deinit();
            const component_t = @TypeOf(new_component);
            _ValidateType(component_t);

            std.debug.assert(self.IsActiveEntity(entity_id));

            return try self.mComponentManager.AddComponent(engine_allocator, entity_id, new_component);
        }

        /// Queues the removal. The component stays readable until ProcessEvents runs.
        pub fn RemoveComponent(self: *Self, engine_context: *EngineContext, entity_id: entity_t, component_ind: usize) !void {
            std.debug.assert(self.IsActiveEntity(entity_id));
            std.debug.assert(components_types.len + BuiltinComponentCount > component_ind);
            std.debug.assert(component_ind != SkipFieldComponent.Ind); // entity lifetime goes through DestroyEntity
            const zone = Tracy.ZoneInit("ECSM RemoveComponent", @src());
            defer zone.Deinit();

            try self.mECSEventManager.Insert(engine_context.EngineAllocator(), .EndOfFrame, .{ .RemoveComponent = .{ .mEntityID = entity_id, .mComponentInd = component_ind } });
        }

        pub fn HasComponent(self: Self, comptime ComponentType: type, entity_id: entity_t) bool {
            _ValidateType(ComponentType);
            std.debug.assert(self.IsActiveEntity(entity_id));
            const zone = Tracy.ZoneInit("ECSM HasComponent", @src());
            defer zone.Deinit();
            return self.mComponentManager.HasComponent(ComponentType, entity_id);
        }

        pub fn GetComponent(self: Self, comptime component_type: type, entity_id: entity_t) ?*component_type {
            _ValidateType(component_type);
            std.debug.assert(self.IsActiveEntity(entity_id));

            const zone = Tracy.ZoneInit("ECSM GetComponent", @src());
            defer zone.Deinit();
            return self.mComponentManager.GetComponent(component_type, entity_id);
        }
        /// Replaces a component with a new value, deinitializing the old one.
        pub fn ResetComponent(self: *Self, engine_context: *EngineContext, entity_id: entity_t, component: anytype) !void {
            const zone = Tracy.ZoneInit("ECSM::ResetComponent", @src());
            defer zone.Deinit();
            _ValidateType(@TypeOf(component));

            std.debug.assert(self.IsActiveEntity(entity_id));

            try self.mComponentManager.ResetComponent(engine_context, entity_id, component);
        }

        /// Runs every queued event of this category, then empties the queue.
        /// The ECS applies the removals itself, after the listeners in `callback_list` have seen the event.
        pub fn ProcessEvents(self: *Self, engine_context: *EngineContext, comptime event_category: ECSEventDataT.EventCategories, callback_list: ECSCallbackList) !void {
            const zone = Tracy.ZoneInit("ECSM ProcessEvents", @src());
            defer zone.Deinit();

            var callbacks = callback_list;

            // appended last so listeners still see a live entity, and unlinked again on the way out
            // because the nodes are shared with the caller's list
            var event_callback = ECSEventCallback{ .mCtx = self, .mCallbackFn = OnECSEvent };
            callbacks.append(&event_callback.mNode);
            defer callbacks.remove(&event_callback.mNode);

            try self.mECSEventManager.ProcessCategory(event_category, engine_context, callbacks);

            self.mECSEventManager.ClearCategory(engine_context.EngineAllocator(), event_category, .ClearRetainingCapacity);
        }

        pub fn OnECSEvent(ecs_manager: *anyopaque, engine_context: *EngineContext, event: *const ECSEventDataT.EventT) anyerror!EventManager.EventResult {
            const self: *Self = @ptrCast(@alignCast(ecs_manager));
            switch (event.*) {
                .DestroyEntity => |e| {
                    try self._InternalDestroyEntity(engine_context, e.mEntityID);
                },
                .RemoveComponent => |e| {
                    try self._InternalRemoveComponent(engine_context, e.mEntityID, e.mComponentInd);
                },
                else => {
                    @panic("Default Events are not allowed!\n");
                },
            }
            return .Continue;
        }

        /// Applies a queued DestroyEntity. Does nothing if the entity is already gone, which happens
        /// when the same destroy was queued twice in one batch.
        /// Children and scripts are not destroyed here: each one is queued as its own event so that
        /// listeners hear about it, and gets destroyed when that event comes up in this same pass.
        fn _InternalDestroyEntity(self: *Self, engine_context: *EngineContext, entity_id: entity_t) anyerror!void {
            if (!self.IsActiveEntity(entity_id)) return;

            const zone = Tracy.ZoneInit("ECSM Internal Destroy Entity", @src());
            defer zone.Deinit();

            try self._InternalQueueChildren(engine_context, entity_id, .Entity);
            try self._InternalQueueChildren(engine_context, entity_id, .Script);

            try self._InternalRemoveFromHierarchy(engine_context, entity_id);
            try self.mComponentManager.DestroyEntity(engine_context, entity_id);
        }

        // queues a destroy for every child in one of this entity's two lists
        fn _InternalQueueChildren(self: *Self, engine_context: *EngineContext, entity_id: entity_t, child_type: ChildType) anyerror!void {
            const parent_component = self.GetComponent(ParentComponent, entity_id) orelse return;

            const first_id = switch (child_type) {
                .Entity => parent_component.mFirstEntity,
                .Script => parent_component.mFirstScript,
            };
            if (first_id == std.math.maxInt(entity_t)) return;

            var curr_id = first_id;
            while (true) {
                const next_id = self.GetComponent(ChildComponent, curr_id).?.mNext;

                try self.mECSEventManager.Insert(engine_context.EngineAllocator(), .EndOfFrame, .{ .DestroyEntity = .{ .mEntityID = curr_id } });

                if (next_id == first_id) break; // the list is circular
                curr_id = next_id;
            }
        }

        /// Applies a queued RemoveComponent. Does nothing if the entity or the component is already gone,
        /// which happens when the entity was destroyed, or the same removal was queued twice, in one batch.
        fn _InternalRemoveComponent(self: *Self, engine_context: *EngineContext, entity_id: entity_t, component_ind: usize) anyerror!void {
            if (!self.IsActiveEntity(entity_id)) return;
            if (!self.mComponentManager.mComponentsArrays.items[component_ind].HasComponent(entity_id)) return;

            const zone = Tracy.ZoneInit("ECSM Internal Remove Component", @src());
            defer zone.Deinit();

            try self.mComponentManager.RemoveComponent(engine_context, entity_id, component_ind);
        }

        // takes this entity out of its parent's child or script list, leaving that list valid
        fn _InternalRemoveFromHierarchy(self: *Self, engine_context: *EngineContext, entity_id: entity_t) anyerror!void {
            std.debug.assert(self.IsActiveEntity(entity_id));
            const zone = Tracy.ZoneInit("ECSM Internal Remove From Hierarchy", @src());
            defer zone.Deinit();

            const child_component = self.GetComponent(ChildComponent, entity_id) orelse return;

            const parent_entity: entity_t = child_component.mParent;
            // the parent goes first when a whole subtree is destroyed, so there may be no list left to leave
            if (!self.IsActiveEntity(parent_entity)) return;

            const parent_component = self.GetComponent(ParentComponent, parent_entity) orelse return;

            const next_id = child_component.mNext;
            const prev_id = child_component.mPrev;

            // scripts and entities are two separate lists hanging off the same ParentComponent
            const is_script = self.HasComponent(ScriptTagComponent, entity_id);
            const first_id = if (is_script) parent_component.mFirstScript else parent_component.mFirstEntity;

            if (next_id == entity_id) {
                // only child in its list, so the list is now empty
                if (is_script) {
                    parent_component.mFirstScript = std.math.maxInt(entity_t);
                } else {
                    parent_component.mFirstEntity = std.math.maxInt(entity_t);
                }
            } else {
                // relink the siblings around this child
                const next_comp = self.GetComponent(ChildComponent, next_id).?;
                const prev_comp = self.GetComponent(ChildComponent, prev_id).?;
                next_comp.mPrev = prev_id;
                prev_comp.mNext = next_id;

                // if this child was the first, the list now starts at the next one
                if (first_id == entity_id) {
                    if (is_script) {
                        parent_component.mFirstScript = next_id;
                    } else {
                        parent_component.mFirstEntity = next_id;
                    }

                    self._InternalSetListFirst(next_id);
                }
            }

            // with both lists empty the parent is no longer a parent.
            // goes straight to the component manager so this internal bookkeeping does not raise an event
            if (parent_component.mFirstEntity == std.math.maxInt(entity_t) and parent_component.mFirstScript == std.math.maxInt(entity_t)) {
                try self.mComponentManager.RemoveComponent(engine_context, parent_entity, ParentComponent.Ind);
            }
        }

        // every child carries the head of its list in mFirst, so moving the head updates all of them
        fn _InternalSetListFirst(self: *Self, first_id: entity_t) void {
            var curr_id = first_id;
            while (true) {
                const curr_component = self.GetComponent(ChildComponent, curr_id).?;
                curr_component.mFirst = first_id;

                curr_id = curr_component.mNext;
                if (curr_id == first_id) break; // the list is circular
            }
        }

        fn _ValidateCompList(comptime component_list: []const type) void {
            inline for (component_list) |component_type| {
                const type_name = std.fmt.comptimePrint(" {s}", .{@typeName(component_type)});
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
                if (component_type.Ind < BuiltinComponentCount) {
                    @compileError(type_name ++ "Type's 'Ind' must be at least " ++ std.fmt.comptimePrint("{d}", .{BuiltinComponentCount}) ++ " because 0 is parent component, 1 is child component, 2 is skipfield component, 3 is MainObjectComponent, 4 is entity tag, 5 is script tag");
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
                    if (fn_info.param_types.len != 2) {
                        @compileError(type_name ++ "'s Deinit must have 2 parameters");
                    }

                    const first_param = fn_info.param_types[0].?;
                    if (first_param != *component_type) {
                        @compileError(type_name ++ "'s Deinit's first parameter must be *type right now it is " ++ @typeName(first_param));
                    }

                    const second_param = fn_info.param_types[1].?;
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

                // Clone is optional: a component that owns memory declares it so DuplicateEntity makes a real
                // copy instead of a second pointer to the same memory. Everything else is copied by value.
                if (@hasDecl(component_type, "Clone")) {
                    const clone_info = @typeInfo(@TypeOf(component_type.Clone));
                    if (clone_info != .@"fn") {
                        @compileError(type_name ++ "'s Clone must be a function ");
                    }

                    const fn_info = clone_info.@"fn";
                    if (fn_info.param_types.len != 2) {
                        @compileError(type_name ++ "'s Clone must have 2 parameters");
                    }

                    const first_param = fn_info.param_types[0].?;
                    if (first_param != *const component_type) {
                        @compileError(type_name ++ "'s Clone's first parameter must be *const type right now it is " ++ @typeName(first_param));
                    }

                    const second_param = fn_info.param_types[1].?;
                    if (second_param != *EngineContext) {
                        @compileError(type_name ++ "'s Clone's second parameter must be *EngineContext currently " ++ @typeName(second_param));
                    }

                    const return_type_info = @typeInfo(fn_info.return_type.?);
                    if (return_type_info != .error_union) {
                        @compileError(type_name ++ "'s Clone's return type must be error union");
                    }

                    const payload_type = return_type_info.error_union.payload;
                    if (payload_type != component_type) {
                        @compileError(type_name ++ "'s Clone's return payload must be the component itself, currently " ++ @typeName(payload_type));
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
            if (component_type == ParentComponent or component_type == ChildComponent or component_type == SkipFieldComponent or component_type == MainObjectComponent or component_type == EntityTagComponent or component_type == ScriptTagComponent) {
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
                    _ValidateGroupQuery(not.mFirst.*);
                    _ValidateGroupQuery(not.mSecond.*);
                },
                .Or => |ors| {
                    if (ors.len < 1) {
                        @compileError("Must have 1 or more in ors group");
                    }
                    inline for (ors) |or_query| {
                        _ValidateGroupQuery(or_query);
                    }
                },
                .And => |ands| {
                    if (ands.len < 1) {
                        @compileError("Must have 1 or more in ands group");
                    }
                    inline for (ands) |and_query| {
                        _ValidateGroupQuery(and_query);
                    }
                },
            }
        }
    };
}
