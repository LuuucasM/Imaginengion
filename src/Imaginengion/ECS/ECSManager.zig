const std = @import("std");
const ComponentManager = @import("ComponentManager.zig").ComponentManager;
const Transaction = @import("Transaction.zig");
const Transactions = @import("Transactions.zig");
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

pub fn ECSManager(entity_t: type, comptime components_types: []const type, comptime debug_name: [:0]const u8) type {
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
        /// A component's slot in THIS manager's arrays; see ComponentManager.ComponentInd.
        pub const ComponentInd = ComponentManagerT.ComponentInd;
        /// The components this ECS was made with, builtins not included.
        pub const ComponentTypes = components_types;
        pub const ECSCallbackList = ECSEventManager.CallbackList;
        pub const ECSEventCallback = ECSEventManager.EventCallback;
        const Self = @This();

        pub const empty: Self = .{
            .mNextID = 0,
            .mComponentManager = .empty,
            .mECSEventManager = .empty,
            .mStagingArena = .init,
            .mStaged = .empty,
            .mRemovalHook = null,
            .mRunDepth = null,
            .mTransactions = null,
        };

        /// Told about each removal and destroy just before it happens, made right away or drained from the queue,
        /// while what goes is still readable. Set once by what owns this ECS (Manager.Core hooks its
        /// OnComponentRemoved and OnObjectDestroyed in), the way the sync callback is
        pub const RemovalHook = struct {
            mCtx: *anyopaque,
            mFn: *const fn (*anyopaque, *EngineContext, ECSEventDataT.EventT) anyerror!void,
        };

        /// A staged component's place in mStaged
        const StagedKey = struct {
            mEntityID: entity_t,
            mComponentInd: usize,
        };

        mNextID: entity_t = 0,
        mComponentManager: ComponentManagerT,
        mECSEventManager: ECSEventManager,
        /// Where AddComponent keeps a component until ProcessEvents puts it on its entity. Reset after every
        /// ProcessEvents, so a staged component's pointer is good until then.
        mStagingArena: std.heap.ArenaAllocator.State,
        /// Every component staged by AddComponent and not yet put on its entity, so GetComponent and HasComponent
        /// find it in the meantime. It is also the record of what is still staged: a queued add whose component is
        /// no longer listed here (taken back off by RemoveComponentSync) is skipped.
        mStaged: std.AutoHashMapUnmanaged(StagedKey, *anyopaque),
        mRemovalHook: ?RemovalHook,
        /// How many runs of the systems layer are going on now, shared by every ECS it knows, null for one it doesn't. While
        /// any is, this ECS holds off structural changes, for whatever keeps pointers, slices or lists of ids into its storage:
        ///   - an add is staged (see AddComponent)
        ///   - a removal or a destroy is queued
        /// Once anything is queued everything after it is queued as well, so changes always land in the order they were
        /// asked for. Tags are the exception, with no storage to move, and so are parents and children, linked as they are
        /// asked for: both are always made right away.
        mRunDepth: ?*const u32,
        /// The transactions layer (Transactions), null for an ECS it doesn't know. While a transaction is open on the calling
        /// thread (Transactions.Current), components are read and changed through it, see Transaction
        mTransactions: ?*const Transactions,

        pub fn Init(self: *Self, engine_allocator: std.mem.Allocator) !void {
            _ValidateCompList(components_types);
            const zone = Tracy.ZoneInit(debug_name ++ "::Init", @src());
            defer zone.Deinit();
            try self.mComponentManager.Init(engine_allocator);
        }

        pub fn Deinit(self: *Self, engine_context: *EngineContext) void {
            const zone = Tracy.ZoneInit(debug_name ++ "::Deinit", @src());
            defer zone.Deinit();
            // staged components go first: like any component, their Deinit can reach into the arrays
            self._DeinitStagedAdds(engine_context);
            self.mComponentManager.Deinit(engine_context);
            self.mECSEventManager.Deinit(engine_context.EngineAllocator());
            self.mStagingArena.promote(engine_context.EngineAllocator()).deinit();
            self.mStaged.deinit(engine_context.EngineAllocator());
        }

        pub fn SetRemovalHook(self: *Self, hook: RemovalHook) void {
            self.mRemovalHook = hook;
        }

        /// Points this ECS manager's event manager at the engine-wide synchronous listener.
        pub fn SetSyncCallback(self: *Self, ctx: anytype, comptime handler: anytype) void {
            self.mECSEventManager.SetSyncCallback(ctx, handler);
        }

        pub fn clearAndFree(self: *Self, engine_context: *EngineContext) void {
            const zone = Tracy.ZoneInit(debug_name ++ "::clearAndFree", @src());
            defer zone.Deinit();
            // staged components go first, same as Deinit
            self._DeinitStagedAdds(engine_context);
            self.mComponentManager.clearAndFree(engine_context);
            // pending events refer to entities that no longer exist
            self.mECSEventManager.EventsReset(engine_context.EngineAllocator(), .ClearAndFree);
            self._ResetStagingArena(engine_context.EngineAllocator());
            self.mNextID = 0;
        }

        /// Deep copies this ECS into `other`, which must be initialized and empty.
        /// Every entity keeps its id, generation included, so ids held outside the ECS still point at
        /// the right entity in the copy: the manager's UUID map, and components naming objects that
        /// live in another manager of the same world.
        pub fn Copy(self: *Self, engine_context: *EngineContext, other: *Self) !void {
            const zone = Tracy.ZoneInit(debug_name ++ "::Copy", @src());
            defer zone.Deinit();

            std.debug.assert(other.mNextID == 0);

            // leaves other empty again, staged adds and all
            errdefer other.clearAndFree(engine_context);

            try self.mComponentManager.CopyInto(engine_context, &other.mComponentManager);

            // queued events name entities by id, which the copy shares, so they carry over as they are. Except that
            // a queued add also points into this ECS's staging arena, so each one is given a clone of its own there
            try self.mECSEventManager.CopyInto(engine_context.EngineAllocator(), &other.mECSEventManager);
            try other._CloneCopiedAdds(engine_context, self);

            other.mNextID = self.mNextID;
        }

        /// How many entity slots there are: every entity's SlotOf is below it, so a table of this many, indexed by
        /// SlotOf, has a place for each entity
        pub fn SlotCount(self: *const Self) usize {
            return @intCast(self.mNextID);
        }

        pub const SlotOf = ComponentManagerT.SlotOf;

        //---------------entity lifetime--------------
        pub fn CreateEntity(self: *Self, engine_allocator: std.mem.Allocator) !entity_t {
            const zone = Tracy.ZoneInit(debug_name ++ "::CreateEntity", @src());
            defer zone.Deinit();

            const new_entity_id = try self._CreateID(engine_allocator);
            _ = try self.mComponentManager.AddComponent(engine_allocator, new_entity_id, EntityTagComponent{});

            return new_entity_id;
        }

        fn CreateScript(self: *Self, engine_allocator: std.mem.Allocator) !entity_t {
            const new_entity_id = try self._CreateID(engine_allocator);
            _ = try self.mComponentManager.AddComponent(engine_allocator, new_entity_id, ScriptTagComponent{});

            return new_entity_id;
        }

        // returns an active id that has only its SkipFieldComponent, reusing a destroyed id when there is one. An open
        // transaction writes it down, to destroy it if it is dropped. A speculating one refuses (error.RunSerially): ids
        // come from the shared free list, and the hook is run again on its own
        fn _CreateID(self: *Self, engine_allocator: std.mem.Allocator) !entity_t {
            const transaction = self._OpenTransaction();
            if (transaction) |open| {
                if (open.RefuseSpeculative()) |err| return err;
                try open.ReserveCreated();
            }

            const new_entity_id = self.mComponentManager.ReuseFreeEntity() orelse blk: {
                const next_id = self.mNextID;
                std.debug.assert(!self.IsActiveEntity(next_id));

                try self.mComponentManager.CreateNewEntity(engine_allocator, next_id);
                self.mNextID += 1; // only consume the id once it has actually been created
                break :blk next_id;
            };

            if (transaction) |open| open.AddCreated(.{ .mECS = self, .mEntityID = new_entity_id, .mUndo = _DestroyCreated });
            return new_entity_id;
        }

        /// Destroys the entity and everything under it, its children and scripts, right away. Queued instead while a run
        /// goes on (see mRunDepth), or when something is queued already.
        pub fn DestroyEntity(self: *Self, engine_context: *EngineContext, entity_id: entity_t) !void {
            std.debug.assert(self.IsActiveEntity(entity_id));
            if (self._OpenTransaction()) |transaction| return try self._Hold(transaction, self._HeldOp(.Destroy, entity_id, 0));
            if (self._Queues()) {
                try self._Enqueue(engine_context.EngineAllocator(), .{ .DestroyEntity = .{ .mEntityID = entity_id } });
                return;
            }
            try self._DestroyNow(engine_context, entity_id);
        }

        /// Every active entity, because they all carry a SkipFieldComponent.
        pub fn GetAllEntities(self: Self, allocator: std.mem.Allocator) !std.ArrayList(entity_t) {
            return try self.GetGroup(allocator, .{ .Component = SkipFieldComponent });
        }

        /// Copies an entity along with its children and scripts, the components staged on them included. The copies
        /// are made now, and their components added the way AddComponent adds them.
        /// The copy joins the original's parent as another child, or becomes a root when the original is one.
        pub fn DuplicateEntity(self: *Self, engine_context: *EngineContext, original_entity_id: entity_t) !entity_t {
            std.debug.assert(self.IsActiveEntity(original_entity_id));
            const zone = Tracy.ZoneInit(debug_name ++ "::DuplicateEntity", @src());
            defer zone.Deinit();

            const engine_allocator = engine_context.EngineAllocator();
            const child_type: ChildType = if (self.HasComponent(ScriptTagComponent, original_entity_id)) .Script else .Entity;

            const new_entity_id = if (self.GetComponent(ChildComponent, original_entity_id)) |child_component|
                try self.AddChild(engine_context, child_component.mParent, child_type)
            else switch (child_type) {
                .Entity => try self.CreateEntity(engine_allocator),
                .Script => try self.CreateScript(engine_allocator),
            };

            try self._InternalDuplicateInto(engine_context, original_entity_id, new_entity_id);

            return new_entity_id;
        }

        // stages a copy of one entity's components and subtree onto another, already created, entity
        fn _InternalDuplicateInto(self: *Self, engine_context: *EngineContext, original_entity_id: entity_t, new_entity_id: entity_t) anyerror!void {
            const engine_allocator = engine_context.EngineAllocator();

            // iterated from a copy, since nothing here needs the original's own one
            var original_skipfield = self.GetComponent(SkipFieldComponent, original_entity_id).?.mSkipField;

            var field_iter = original_skipfield.Iterator();
            while (field_iter.next()) |component_ind| {
                // the copy has its own tag from being created, and its own place in the hierarchy from its link
                if (component_ind == ParentComponent.Ind) continue;
                if (component_ind == ChildComponent.Ind) continue;
                if (component_ind == SkipFieldComponent.Ind) continue;
                if (component_ind == EntityTagComponent.Ind) continue;
                if (component_ind == ScriptTagComponent.Ind) continue;

                var staging_arena = self.mStagingArena.promote(engine_allocator);
                defer self.mStagingArena = staging_arena.state;
                const staged_component = try self.mComponentManager.StageDuplicate(engine_context, staging_arena.allocator(), component_ind, original_entity_id);
                try self._StageOrAddCopy(engine_context, new_entity_id, component_ind, staged_component);
            }

            // and the ones still staged for it. Indexed rather than sliced, since staging the copies below appends to
            // this same queue, and only up to its length now, so the copies' own adds aren't copied again
            const queued_adds = self.mECSEventManager.mEventsArray.getPtr(.EndOfFrame);
            const queued_count = queued_adds.items.len;
            for (0..queued_count) |event_ind| {
                const add = switch (queued_adds.items[event_ind]) {
                    .AddComponent => |add| add,
                    else => continue,
                };
                if (add.mEntityID != original_entity_id) continue;
                if (self._GetStaged(original_entity_id, add.mComponentInd) != add.mData) continue; // taken back off

                var staging_arena = self.mStagingArena.promote(engine_allocator);
                defer self.mStagingArena = staging_arena.state;
                const staged_component = try self.mComponentManager.CloneStaged(engine_context, staging_arena.allocator(), add.mComponentInd, add.mData);
                try self._StageOrAddCopy(engine_context, new_entity_id, add.mComponentInd, staged_component);
            }

            try self._InternalDuplicateChildren(engine_context, original_entity_id, new_entity_id, .Entity);
            try self._InternalDuplicateChildren(engine_context, original_entity_id, new_entity_id, .Script);
        }

        // puts a copy made in the staging arena on the duplicate: staged if it has to wait, the way AddComponent
        // decides, and right away otherwise
        fn _StageOrAddCopy(self: *Self, engine_context: *EngineContext, new_entity_id: entity_t, component_ind: usize, staged_component: *anyopaque) !void {
            // the clone is this ECS's until it is on the entity or queued
            errdefer self.mComponentManager.DeinitStaged(engine_context, component_ind, staged_component);
            if (self._OpenTransaction()) |transaction| {
                if (self.mComponentManager.IsTag(component_ind)) return try self._Hold(transaction, self._HeldTag(new_entity_id, component_ind, true));
                var op = self._HeldOp(.Add, new_entity_id, component_ind);
                op.mData = staged_component;
                return try self._Hold(transaction, op);
            }
            if (self.mComponentManager.IsTag(component_ind) or !self._Queues()) {
                self._CheckStorageChange(component_ind, "Adding");
                try self.mComponentManager.AddStaged(engine_context.EngineAllocator(), new_entity_id, component_ind, staged_component);
            } else {
                try self._QueueStagedAdd(engine_context.EngineAllocator(), new_entity_id, component_ind, staged_component);
            }
        }

        fn _InternalDuplicateChildren(self: *Self, engine_context: *EngineContext, original_entity_id: entity_t, new_entity_id: entity_t, child_type: ChildType) anyerror!void {
            const first_id = blk: {
                // only the id is kept, the pointer is not needed past this
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

                const new_child_id = try self.AddChild(engine_context, new_entity_id, child_type);
                try self._InternalDuplicateInto(engine_context, curr_id, new_child_id);

                if (next_id == first_id) break; // the list is circular
                curr_id = next_id;
            }
        }

        pub fn IsActiveEntity(self: Self, entity_id: entity_t) bool {
            return self.mComponentManager.IsActiveEntity(entity_id);
        }

        /// How many entities currently have `component_type`, without building a group.
        pub fn NumWithComponent(self: Self, comptime component_type: type) usize {
            _ValidateType(component_type);
            if (self._Measuring()) |transaction| self._NoteTypeRead(transaction, component_type, .Membership);
            var count = self.mComponentManager.NumWithComponent(component_type);
            if (self.mStaged.count() > 0) {
                var staged_keys = self.mStaged.keyIterator();
                while (staged_keys.next()) |key| {
                    if (key.mComponentInd == ComponentInd(component_type)) count += 1;
                }
            }
            if (self._OpenTransaction()) |transaction| count = self._CountHeld(transaction, ComponentInd(component_type), count);
            return count;
        }

        /// Every `component_type` in this ECS, for a pass over all of them that has no use for the
        /// ids. Only good until a component of that type is added or removed.
        pub fn GetComponentSlice(self: Self, comptime component_type: type) []const component_type {
            _ValidateType(component_type);
            if (self._Measuring()) |transaction| self._NoteTypeRead(transaction, component_type, .Values);
            return self.mComponentManager.GetComponentSlice(component_type);
        }

        /// GetComponentSlice for changing them. Not while a transaction is open: a change made straight to storage
        /// couldn't be taken back, and safe builds panic
        pub fn GetComponentSliceMut(self: Self, comptime component_type: type) []component_type {
            _ValidateType(component_type);
            if (std.debug.runtime_safety and (comptime _Copies(component_type)) and self._OpenTransaction() != null) {
                std.debug.panic("GetComponentSliceMut({s}) inside a transaction: a change to the slice couldn't be taken back", .{@typeName(component_type)});
            }
            if (self._Measuring()) |transaction| self._NoteTypeRead(transaction, component_type, .Values);
            return self.mComponentManager.GetComponentSlice(component_type);
        }

        //for getting groups of entities
        pub fn GetGroup(self: Self, allocator: std.mem.Allocator, comptime query: GroupQuery) !std.ArrayList(entity_t) {
            _ValidateGroupQuery(query);
            if (self._Measuring()) |transaction| self._NoteQueryReads(transaction, query);
            const zone = Tracy.ZoneInit(debug_name ++ "::GetGroup", @src());
            defer zone.Deinit();

            var result = try self.mComponentManager.GetGroup(query, allocator);
            const holds = if (self._OpenTransaction()) |transaction| transaction.mPresence.count() > 0 else false;
            if (self.mStaged.count() > 0 or holds) try self._AddStagedToGroup(allocator, query, &result);
            return result;
        }

        // storage only knows what has landed, so each entity with something staged, or held by the open transaction, is
        // asked again with that counted: it joins the group if that makes it match, and leaves if that stops it matching
        // (a tag held off, the second half of a Not)
        fn _AddStagedToGroup(self: Self, allocator: std.mem.Allocator, comptime query: GroupQuery, result: *std.ArrayList(entity_t)) !void {
            var entity_ids: std.ArrayList(entity_t) = .empty;
            defer entity_ids.deinit(allocator);
            try entity_ids.ensureTotalCapacity(allocator, self.mStaged.count());
            var staged_keys = self.mStaged.keyIterator();
            while (staged_keys.next()) |key| entity_ids.appendAssumeCapacity(key.mEntityID);
            if (self._OpenTransaction()) |transaction| {
                for (transaction.mOps.items) |op| {
                    if (op.mDone or (op.mKind != .Add and op.mKind != .Tag) or !self._IsOwnArray(op)) continue;
                    try entity_ids.append(allocator, @intCast(op.mEntityID));
                }
            }
            //by id, each once, so a group comes out the same every run
            std.mem.sort(entity_t, entity_ids.items, {}, std.sort.asc(entity_t));

            var previous: ?entity_t = null;
            for (entity_ids.items) |entity_id| {
                if (previous == entity_id) continue;
                previous = entity_id;
                const in_storage = self._MatchesQuery(query, entity_id, false);
                const with_staged = self.IsActiveEntity(entity_id) and self._MatchesQuery(query, entity_id, true);
                if (with_staged and !in_storage) {
                    try result.append(allocator, entity_id);
                } else if (in_storage and !with_staged) {
                    const index = std.mem.indexOfScalar(entity_t, result.items, entity_id).?;
                    _ = result.orderedRemove(index);
                }
            }
        }

        fn _MatchesQuery(self: Self, comptime query: GroupQuery, entity_id: entity_t, count_staged: bool) bool {
            switch (query) {
                .Component => |component_type| {
                    const component_ind = ComponentInd(component_type);
                    if (count_staged) {
                        if (self._HeldPresence(component_ind, entity_id)) |op| return _HeldOn(op);
                    }
                    if (self.mComponentManager.HasComponentInd(component_ind, entity_id)) return true;
                    return count_staged and self._GetStaged(entity_id, component_ind) != null;
                },
                .And => |queries| {
                    inline for (queries) |sub_query| {
                        if (!self._MatchesQuery(sub_query, entity_id, count_staged)) return false;
                    }
                    return true;
                },
                .Or => |queries| {
                    inline for (queries) |sub_query| {
                        if (self._MatchesQuery(sub_query, entity_id, count_staged)) return true;
                    }
                    return false;
                },
                .Not => |not| return self._MatchesQuery(not.mFirst.*, entity_id, count_staged) and !self._MatchesQuery(not.mSecond.*, entity_id, count_staged),
            }
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

        /// Makes the child and links it under `entity_id`, at the end of its entity or script list, before returning.
        /// Linking adds a ChildComponent, and maybe a ParentComponent, right away rather than staging them: a new
        /// tree has to be walkable as soon as it is built. Only the hierarchy code holds pointers into those arrays,
        /// and it fetches them again after every add.
        pub fn AddChild(self: *Self, engine_context: *EngineContext, entity_id: entity_t, child_type: ChildType) !entity_t {
            std.debug.assert(self.IsActiveEntity(entity_id));

            const zone = Tracy.ZoneInit(debug_name ++ "::AddChild", @src());
            defer zone.Deinit();

            const engine_allocator = engine_context.EngineAllocator();
            const new_entity_id = switch (child_type) {
                .Entity => try self.CreateEntity(engine_allocator),
                .Script => try self.CreateScript(engine_allocator),
            };

            try self._InternalLinkChild(engine_context, entity_id, new_entity_id);

            return new_entity_id;
        }

        /// Puts a child at the end of its parent's entity or script list, which one going by the child's tag.
        fn _InternalLinkChild(self: *Self, engine_context: *EngineContext, entity_id: entity_t, new_entity_id: entity_t) !void {
            std.debug.assert(self.IsActiveEntity(entity_id));
            std.debug.assert(self.IsActiveEntity(new_entity_id));
            std.debug.assert(!self.HasComponent(ChildComponent, new_entity_id));

            const child_type: ChildType = if (self.HasComponent(ScriptTagComponent, new_entity_id)) .Script else .Entity;

            if (self.GetComponentMut(ParentComponent, entity_id)) |parent_component| {
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
                    _ = try self.AddComponentSync(engine_context, new_entity_id, new_child_component);

                    // both are the same component when the parent only had one child, which is still correct
                    const first_child_component = self.GetComponentMut(ChildComponent, first_child_entity_id).?;
                    const last_child_component = self.GetComponentMut(ChildComponent, last_child_entity_id).?;

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

                    _ = try self.AddComponentSync(engine_context, new_entity_id, new_child_component);
                }
            } else {
                const new_parent_component = switch (child_type) {
                    .Entity => ParentComponent{ .mFirstEntity = new_entity_id },
                    .Script => ParentComponent{ .mFirstScript = new_entity_id },
                };

                _ = try self.AddComponentSync(engine_context, entity_id, new_parent_component);

                const new_child_component = ChildComponent{
                    .mFirst = new_entity_id,
                    .mNext = new_entity_id,
                    .mParent = entity_id,
                    .mPrev = new_entity_id,
                };

                _ = try self.AddComponentSync(engine_context, new_entity_id, new_child_component);
            }
        }

        /// Points this ECS at the systems layer's count of runs going on (null to stop), see mRunDepth
        pub fn SetRunDepth(self: *Self, run_depth: ?*const u32) void {
            self.mRunDepth = run_depth;
        }

        /// Points this ECS at the transactions layer (null to stop), see mTransactions
        pub fn SetTransactions(self: *Self, transactions: ?*const Transactions) void {
            self.mTransactions = transactions;
        }

        // the transaction open now, if there is one
        // the open transaction, if it is writing down what it reads and writes for the conflict report (Transactions.mConflicts)
        fn _Measuring(self: Self) ?*Transaction {
            const transaction = self._OpenTransaction() orelse return null;
            return if (transaction.mMeasuring) transaction else null;
        }

        fn _KeyInd(self: Self, component_ind: usize, entity_id: entity_t) Transaction.Key {
            return .{ .mArray = self.mComponentManager.ArrayOfInd(component_ind), .mEntityID = entity_id };
        }

        fn _NoteRead(self: Self, transaction: *Transaction, component_ind: usize, entity_id: entity_t) void {
            transaction.NoteRead(self._KeyInd(component_ind, entity_id), ComponentNames[component_ind]);
        }

        fn _NoteTypeRead(self: Self, transaction: *Transaction, comptime component_type: type, access: Transaction.TypeAccess) void {
            transaction.NoteTypeRead(self.mComponentManager.ArrayOf(component_type), access, ComponentNames[ComponentInd(component_type)]);
        }

        // which entities have each type a query looks at
        fn _NoteQueryReads(self: Self, transaction: *Transaction, comptime query: GroupQuery) void {
            switch (query) {
                .Component => |component_type| self._NoteTypeRead(transaction, component_type, .Membership),
                .And, .Or => |queries| inline for (queries) |sub_query| self._NoteQueryReads(transaction, sub_query),
                .Not => |not| {
                    self._NoteQueryReads(transaction, not.mFirst.*);
                    self._NoteQueryReads(transaction, not.mSecond.*);
                },
            }
        }

        // in safe builds, a panic when a hook running in a batch does what only the main thread may (Transactions.CheckMainThread)
        fn _CheckMainThread(self: Self, comptime what: []const u8) void {
            const transactions = self.mTransactions orelse return;
            transactions.CheckMainThread(what);
        }

        fn _OpenTransaction(self: Self) ?*Transaction {
            const transactions = self.mTransactions orelse return null;
            return transactions.Current();
        }

        // whether a transaction copies this type before it is changed. Tags have no value, and parents, children and the
        // skip field are hierarchy and entity bookkeeping, changed right away like the links they are part of
        fn _Copies(comptime component_type: type) bool {
            if (@sizeOf(component_type) == 0) return false;
            return component_type != ParentComponent and component_type != ChildComponent and component_type != SkipFieldComponent;
        }

        // whether a run of the systems layer is going on, and this ECS is holding its changes for it
        fn _InRun(self: Self) bool {
            const run_depth = self.mRunDepth orelse return false;
            return run_depth.* > 0;
        }

        /// Makes every change this ECS is holding, if there are any, and says whether there were: for the systems layer as
        /// its last run ends
        pub fn LandQueued(self: *Self, engine_context: *EngineContext) !bool {
            if (!self._HasQueued()) return false;
            try self._Drain(engine_context);
            return true;
        }

        /// Whether an add or removal can go straight to this component's storage: a tag has none to move, parents and
        /// children are linked and unlinked as they are asked for, and anything else only outside a run
        pub fn CanChangeStorage(self: Self, component_ind: usize) bool {
            if (self.mComponentManager.IsTag(component_ind)) return true;
            if (component_ind == ParentComponent.Ind or component_ind == ChildComponent.Ind) return true;
            return !self._InRun();
        }

        // in safe builds, a panic when a change reaches storage during a run: it would move what a running system holds
        fn _CheckStorageChange(self: Self, component_ind: usize, comptime change: []const u8) void {
            if (!std.debug.runtime_safety) return;
            self._CheckMainThread("Changing an ECS's storage");
            if (self.CanChangeStorage(component_ind)) return;
            std.debug.panic(change ++ " {s} right away during a run, which would move what a running system holds", .{ComponentNames[component_ind]});
        }

        // each slot's component type name, for _CheckStorageChange's message
        const ComponentNames = blk: {
            var names: [components_types.len + BuiltinComponentCount][]const u8 = undefined;
            for ([_]type{ ParentComponent, ChildComponent, SkipFieldComponent, MainObjectComponent, EntityTagComponent, ScriptTagComponent }) |builtin_type| {
                names[ComponentInd(builtin_type)] = @typeName(builtin_type);
            }
            for (components_types, 0..) |listed_type, listed_ind| names[listed_ind + BuiltinComponentCount] = @typeName(listed_type);
            break :blk names;
        };

        //--------components related functions----------
        // whether a change waits in the queue: a run is going on, or something is queued already
        fn _Queues(self: Self) bool {
            return self._InRun() or self._HasQueued();
        }

        fn _HasQueued(self: Self) bool {
            return self.mECSEventManager.mEventsArray.get(.EndOfFrame).items.len > 0;
        }

        // queues a removal or a destroy
        fn _Enqueue(self: *Self, engine_allocator: std.mem.Allocator, event: ECSEventDataT.EventT) !void {
            self._CheckMainThread("Queueing a removal or a destroy");
            try self.mECSEventManager.Insert(engine_allocator, .EndOfFrame, event);
        }

        //---------------what an open transaction holds until it ends (see Transaction)---------------
        // making or dropping a held change can't fail outright, so what fails is logged and the rest still done

        fn _HeldOp(self: *Self, kind: Transaction.OpKind, entity_id: entity_t, component_ind: usize) Transaction.Op {
            return .{
                .mECS = self,
                .mKind = kind,
                .mEntityID = entity_id,
                .mComponentInd = component_ind,
                .mArray = if (kind == .Add or kind == .Tag) self.mComponentManager.ArrayOfInd(component_ind) else null,
                .mApply = _ApplyHeld,
                .mDrop = _DropHeld,
            };
        }

        fn _HeldTag(self: *Self, entity_id: entity_t, component_ind: usize, on: bool) Transaction.Op {
            var op = self._HeldOp(.Tag, entity_id, component_ind);
            op.mOn = on;
            return op;
        }

        // holds a structural change in the open transaction. An add or a tag is a write the conflict check sees
        fn _Hold(self: *Self, transaction: *Transaction, op: Transaction.Op) !void {
            if (transaction.mMeasuring and (op.mKind == .Add or op.mKind == .Tag)) {
                transaction.NotePresenceWrite(self._KeyInd(op.mComponentInd, @intCast(op.mEntityID)), ComponentNames[op.mComponentInd]);
            }
            try transaction.AddOp(op);
        }

        // the newest add or tag the open transaction holds for this component, null if none (or no transaction)
        fn _HeldPresence(self: Self, component_ind: usize, entity_id: entity_t) ?*Transaction.Op {
            const transaction = self._OpenTransaction() orelse return null;
            return transaction.Presence(self._KeyInd(component_ind, entity_id));
        }

        // whether a held add or tag leaves the component on
        fn _HeldOn(op: *const Transaction.Op) bool {
            return op.mKind == .Add or op.mOn;
        }

        // whether a held op is about one of this ECS's arrays
        fn _IsOwnArray(self: Self, op: Transaction.Op) bool {
            if (op.mComponentInd >= components_types.len + BuiltinComponentCount) return false;
            return self.mComponentManager.ArrayOfInd(op.mComponentInd) == op.mArray.?;
        }

        // `count` (what storage and the stage have of a type) with what the open transaction holds put on or taken off
        fn _CountHeld(self: Self, transaction: *Transaction, component_ind: usize, count: usize) usize {
            var held_count = count;
            const array = self.mComponentManager.ArrayOfInd(component_ind);
            for (transaction.mOps.items, 0..) |op, op_ind| {
                if (op.mDone or op.mArray != array) continue;
                const id: entity_t = @intCast(op.mEntityID);
                // only the newest op for each entity says where it ends up
                if (transaction.mPresence.get(.{ .mArray = array, .mEntityID = op.mEntityID }) != op_ind) continue;
                const before = self.mComponentManager.HasComponentInd(component_ind, id) or self._GetStaged(id, component_ind) != null;
                const after = _HeldOn(&op);
                if (after and !before) held_count += 1;
                if (!after and before) held_count -= 1;
            }
            return held_count;
        }

        // a held tag's no value, for GetComponent: tags have none to hand out
        fn _NoValue(comptime component_type: type) *component_type {
            const Holder = struct {
                var value: component_type = undefined;
            };
            return &Holder.value;
        }

        // makes a held change now its transaction is kept, the way it would have been made straight away: an add staged,
        // a tag put on or taken off, a removal or destroy queued
        fn _ApplyHeld(erased: *anyopaque, engine_context: *EngineContext, op: *Transaction.Op) void {
            const self: *Self = @ptrCast(@alignCast(erased));
            self._ApplyHeldOrFail(engine_context, op) catch |err| std.log.err(debug_name ++ ": making a change a kept transaction held: {s}", .{@errorName(err)});
        }

        fn _ApplyHeldOrFail(self: *Self, engine_context: *EngineContext, op: *Transaction.Op) !void {
            const engine_allocator = engine_context.EngineAllocator();
            const id: entity_t = @intCast(op.mEntityID);
            switch (op.mKind) {
                .Add => {
                    if (!self.IsActiveEntity(id)) return self.mComponentManager.DeinitStaged(engine_context, op.mComponentInd, op.mData.?);
                    var staged = op.mData.?;
                    if (op.mDataInArena) {
                        // the transaction's arena goes with it, so the value moves into the staging arena
                        var staging_arena = self.mStagingArena.promote(engine_allocator);
                        defer self.mStagingArena = staging_arena.state;
                        staged = try self.mComponentManager.MoveStaged(staging_arena.allocator(), op.mComponentInd, staged);
                    }
                    errdefer self.mComponentManager.DeinitStaged(engine_context, op.mComponentInd, staged);
                    if (self._Queues()) {
                        try self._QueueStagedAdd(engine_allocator, id, op.mComponentInd, staged);
                    } else {
                        try self.mComponentManager.AddStaged(engine_allocator, id, op.mComponentInd, staged);
                    }
                },
                .Tag => {
                    if (!self.IsActiveEntity(id)) return;
                    const has = self.mComponentManager.HasComponentInd(op.mComponentInd, id);
                    if (op.mOn and !has) {
                        try self.mComponentManager.AddTagInd(engine_allocator, id, op.mComponentInd);
                        var no_value: u8 = 0;
                        _ = try self.mECSEventManager.Dispatch(engine_context, .{ .AddComponent = .{ .mEntityID = id, .mComponentInd = op.mComponentInd, .mData = &no_value } });
                    } else if (!op.mOn and has) {
                        try self._RemoveNow(engine_context, id, op.mComponentInd);
                    }
                },
                .Remove => {
                    if (!self.IsActiveEntity(id)) return;
                    if (self._Queues()) {
                        try self._Enqueue(engine_allocator, .{ .RemoveComponent = .{ .mEntityID = id, .mComponentInd = op.mComponentInd } });
                    } else {
                        try self._RemoveNow(engine_context, id, op.mComponentInd);
                    }
                },
                .Destroy => {
                    if (!self.IsActiveEntity(id)) return;
                    if (self._Queues()) {
                        try self._Enqueue(engine_allocator, .{ .DestroyEntity = .{ .mEntityID = id } });
                    } else {
                        try self._DestroyNow(engine_context, id);
                    }
                },
            }
        }

        // drops a held change now its transaction is: an add, and a tag put on, go through the removal hook on a live
        // object, undoing what asking for them set off (Manager.OnComponentAdded), and an add's value is deinitialized.
        // Removals and destroys were never made
        fn _DropHeld(erased: *anyopaque, engine_context: *EngineContext, op: *Transaction.Op) void {
            const self: *Self = @ptrCast(@alignCast(erased));
            const id: entity_t = @intCast(op.mEntityID);
            switch (op.mKind) {
                .Add, .Tag => {
                    if (_HeldOn(op) and self.IsActiveEntity(id)) {
                        self._CallRemovalHook(engine_context, .{ .RemoveComponent = .{ .mEntityID = id, .mComponentInd = op.mComponentInd } }) catch |err| {
                            std.log.err(debug_name ++ ": undoing what a dropped transaction added: {s}", .{@errorName(err)});
                        };
                    }
                    if (op.mKind == .Add) self.mComponentManager.DeinitStaged(engine_context, op.mComponentInd, op.mData.?);
                },
                .Remove, .Destroy => {},
            }
        }

        // destroys an object a dropped transaction made, and everything under it, right away
        fn _DestroyCreated(erased: *anyopaque, engine_context: *EngineContext, entity_id: u64) void {
            const self: *Self = @ptrCast(@alignCast(erased));
            const id: entity_t = @intCast(entity_id);
            // gone already when its parent, made in the same transaction, went first
            if (!self.IsActiveEntity(id)) return;
            self._DestroyNow(engine_context, id) catch |err| std.log.err(debug_name ++ ": destroying an object a dropped transaction made: {s}", .{@errorName(err)});
        }

        /// Adds the component now, unless it has to wait (see mRunDepth). Then it is staged instead: its storage only
        /// takes it when the queue drains, so no component already in that array moves during a run. Until then
        /// GetComponent, HasComponent, GetGroup and NumWithComponent find the staged copy, which is also what this
        /// returns, so the entity reads as having it straight away. Only GetComponentSlice, which hands back the storage
        /// itself, doesn't see it until it lands.
        /// A tag has no storage that could move, so it always goes on right away.
        pub fn AddComponent(self: *Self, engine_context: *EngineContext, entity_id: entity_t, new_component: anytype) !*@TypeOf(new_component) {
            const component_t = @TypeOf(new_component);
            if (comptime @sizeOf(component_t) == 0) return try self.AddComponentSync(engine_context, entity_id, new_component);
            if (self._OpenTransaction()) |transaction| return try self._HoldAdd(transaction, engine_context, entity_id, new_component);
            if (!self._Queues()) return try self.AddComponentSync(engine_context, entity_id, new_component);

            const zone = Tracy.ZoneInit(debug_name ++ "::AddComponent", @src());
            defer zone.Deinit();
            _ValidateType(component_t);
            std.debug.assert(component_t != SkipFieldComponent); // entity lifetime goes through CreateEntity

            std.debug.assert(self.IsActiveEntity(entity_id));
            // staged twice: only one of the two values can be meant. Having it on the entity already is checked
            // when the add lands instead, since a queued removal of it may land first
            std.debug.assert(self._GetStaged(entity_id, ComponentInd(component_t)) == null);

            const engine_allocator = engine_context.EngineAllocator();

            var staging_arena = self.mStagingArena.promote(engine_allocator);
            defer self.mStagingArena = staging_arena.state;
            const staged_component = try staging_arena.allocator().create(component_t);
            staged_component.* = new_component;

            try self._QueueStagedAdd(engine_allocator, entity_id, ComponentInd(component_t), staged_component);

            return staged_component;
        }

        // AddComponent inside a transaction: the value is held in it until it ends, read as on the entity meanwhile
        fn _HoldAdd(self: *Self, transaction: *Transaction, engine_context: *EngineContext, entity_id: entity_t, new_component: anytype) !*@TypeOf(new_component) {
            const component_t = @TypeOf(new_component);
            _ValidateType(component_t);
            std.debug.assert(component_t != SkipFieldComponent); // entity lifetime goes through CreateEntity
            std.debug.assert(self.IsActiveEntity(entity_id));
            const component_ind = ComponentInd(component_t);
            // asked whether it is there already, so two hooks of a batch adding the same one conflict
            if (transaction.mMeasuring) self._NoteRead(transaction, component_ind, entity_id);
            // staged twice: only one of the two values can be meant
            std.debug.assert(self._GetStaged(entity_id, component_ind) == null);
            if (transaction.Presence(self._KeyInd(component_ind, entity_id))) |held| std.debug.assert(held.mKind != .Add);

            const held = try transaction.Create(component_t);
            held.* = new_component;
            // through the array, so a script DLL's copy of this never compiles the component's own Deinit
            errdefer self.mComponentManager.DeinitStaged(engine_context, component_ind, held);
            var op = self._HeldOp(.Add, entity_id, component_ind);
            op.mData = held;
            op.mDataInArena = true;
            try self._Hold(transaction, op);
            return held;
        }

        // lists a component already in the staging arena under its entity and queues its add
        fn _QueueStagedAdd(self: *Self, engine_allocator: std.mem.Allocator, entity_id: entity_t, component_ind: usize, staged_component: *anyopaque) !void {
            self._CheckMainThread("Staging an add");
            const key = StagedKey{ .mEntityID = entity_id, .mComponentInd = component_ind };
            try self.mStaged.put(engine_allocator, key, staged_component);
            errdefer _ = self.mStaged.remove(key);

            try self.mECSEventManager.Insert(engine_allocator, .EndOfFrame, .{ .AddComponent = .{
                .mEntityID = entity_id,
                .mComponentInd = component_ind,
                .mData = staged_component,
            } });
        }

        // the staged component for this entity and slot, if there is one. Most of the time nothing is staged at all,
        // which is what keeps this from costing GetComponent and HasComponent a lookup
        fn _GetStaged(self: Self, entity_id: entity_t, component_ind: usize) ?*anyopaque {
            if (self.mStaged.count() == 0) return null;
            return self.mStaged.get(.{ .mEntityID = entity_id, .mComponentInd = component_ind });
        }

        /// Adds the component now rather than at end of frame, then hands the sync listener the same AddComponent
        /// event the deferred path raises once its add is applied, so HasComponent is true when this returns.
        ///
        /// Same rule as RemoveComponentSync: use this only where nothing holds a pointer into that component's
        /// storage, since the add can grow the dense array and move every component already in it.
        pub fn AddComponentSync(self: *Self, engine_context: *EngineContext, entity_id: entity_t, new_component: anytype) !*@TypeOf(new_component) {
            const zone = Tracy.ZoneInit(debug_name ++ "::AddComponentSync", @src());
            defer zone.Deinit();
            const component_t = @TypeOf(new_component);
            _ValidateType(component_t);
            std.debug.assert(component_t != SkipFieldComponent); // entity lifetime goes through CreateEntity

            std.debug.assert(self.IsActiveEntity(entity_id));
            std.debug.assert(self._GetStaged(entity_id, ComponentInd(component_t)) == null);

            if (comptime @sizeOf(component_t) == 0) {
                if (self._OpenTransaction()) |transaction| {
                    try self._Hold(transaction, self._HeldTag(entity_id, ComponentInd(component_t), true));
                    return _NoValue(component_t);
                }
            }

            self._CheckStorageChange(ComponentInd(component_t), "Adding");
            const component_ptr = try self.mComponentManager.AddComponent(engine_context.EngineAllocator(), entity_id, new_component);

            _ = try self.mECSEventManager.Dispatch(engine_context, .{ .AddComponent = .{
                .mEntityID = entity_id,
                .mComponentInd = ComponentInd(component_t),
                .mData = component_ptr,
            } });

            // fetched again: the listener can add components of its own, which may have moved this one
            return self.mComponentManager.GetComponent(component_t, entity_id).?;
        }

        /// Removes the component right away, unless it has to wait (see mRunDepth), when the removal is queued and the
        /// component stays readable until the queue drains. A tag always comes off right away.
        pub fn RemoveComponent(self: *Self, engine_context: *EngineContext, entity_id: entity_t, component_ind: usize) !void {
            std.debug.assert(self.IsActiveEntity(entity_id));
            std.debug.assert(components_types.len + BuiltinComponentCount > component_ind);
            std.debug.assert(component_ind != SkipFieldComponent.Ind); // entity lifetime goes through DestroyEntity
            if (self._OpenTransaction()) |transaction| {
                if (self.mComponentManager.IsTag(component_ind)) return try self._Hold(transaction, self._HeldTag(entity_id, component_ind, false));
                return try self._Hold(transaction, self._HeldOp(.Remove, entity_id, component_ind));
            }
            if (self.mComponentManager.IsTag(component_ind) or !self._Queues()) return try self._RemoveNow(engine_context, entity_id, component_ind);
            try self._Enqueue(engine_context.EngineAllocator(), .{ .RemoveComponent = .{ .mEntityID = entity_id, .mComponentInd = component_ind } });
        }

        /// RemoveComponent made right away even during a run. Only where nothing holds a pointer into that
        /// component's storage: the removal swapRemoves from the dense array, which moves another entity's component.
        /// Inside a transaction a tag is held off like any, and an add the transaction holds is dropped. Anything else
        /// taken off this way inside one can't be put back: a speculating one refuses it (error.RunSerially)
        pub fn RemoveComponentSync(self: *Self, engine_context: *EngineContext, entity_id: entity_t, component_ind: usize) !void {
            std.debug.assert(self.IsActiveEntity(entity_id));
            std.debug.assert(components_types.len + BuiltinComponentCount > component_ind);
            std.debug.assert(component_ind != SkipFieldComponent.Ind); // entity lifetime goes through DestroyEntity
            if (self._OpenTransaction()) |transaction| {
                if (self.mComponentManager.IsTag(component_ind)) return try self._Hold(transaction, self._HeldTag(entity_id, component_ind, false));
                if (transaction.Presence(self._KeyInd(component_ind, entity_id))) |held| {
                    if (held.mKind == .Add) {
                        held.mDone = true;
                        _DropHeld(self, engine_context, held);
                        return;
                    }
                }
                if (transaction.RefuseSpeculative()) |err| return err;
            }
            try self._RemoveNow(engine_context, entity_id, component_ind);
        }

        // the removal itself: the hook hears of it first, while the component can still be read. The one on the entity
        // is the one taken off, even with an add of it staged behind this removal; one that is only staged is taken back
        // off the stage instead, and its queued add skipped. Nothing for one that is gone
        fn _RemoveNow(self: *Self, engine_context: *EngineContext, entity_id: entity_t, component_ind: usize) !void {
            const removes_live = self.mComponentManager.HasComponentInd(component_ind, entity_id);
            if (!removes_live and self._GetStaged(entity_id, component_ind) == null) return;

            const zone = Tracy.ZoneInit(debug_name ++ "::RemoveComponent", @src());
            defer zone.Deinit();

            try self._CallRemovalHook(engine_context, .{ .RemoveComponent = .{ .mEntityID = entity_id, .mComponentInd = component_ind } });

            if (removes_live) {
                // the hook may have taken it off itself
                if (self.mComponentManager.HasComponentInd(component_ind, entity_id)) {
                    self._CheckStorageChange(component_ind, "Removing");
                    self.mComponentManager.RemoveComponent(engine_context, entity_id, component_ind);
                }
                return;
            }
            if (self.mStaged.fetchRemove(.{ .mEntityID = entity_id, .mComponentInd = component_ind })) |staged| {
                self.mComponentManager.DeinitStaged(engine_context, component_ind, staged.value);
            }
        }

        fn _CallRemovalHook(self: *Self, engine_context: *EngineContext, event: ECSEventDataT.EventT) !void {
            const hook = self.mRemovalHook orelse return;
            try hook.mFn(hook.mCtx, engine_context, event);
        }

        /// True for a component that is staged as well (see AddComponent)
        pub fn HasComponent(self: Self, comptime ComponentType: type, entity_id: entity_t) bool {
            _ValidateType(ComponentType);
            std.debug.assert(self.IsActiveEntity(entity_id));
            if (self._Measuring()) |transaction| self._NoteRead(transaction, ComponentInd(ComponentType), entity_id);
            if (self._HeldPresence(ComponentInd(ComponentType), entity_id)) |op| return _HeldOn(op);
            return self.mComponentManager.HasComponent(ComponentType, entity_id) or
                self._GetStaged(entity_id, ComponentInd(ComponentType)) != null;
        }

        /// HasComponent for a component known only by its slot (ComponentInd) at runtime
        pub fn HasComponentInd(self: Self, component_ind: usize, entity_id: entity_t) bool {
            std.debug.assert(self.IsActiveEntity(entity_id));
            if (self._Measuring()) |transaction| self._NoteRead(transaction, component_ind, entity_id);
            if (self._HeldPresence(component_ind, entity_id)) |op| return _HeldOn(op);
            return self.mComponentManager.HasComponentInd(component_ind, entity_id) or
                self._GetStaged(entity_id, component_ind) != null;
        }

        /// The staged copy for a component that is still staged (see AddComponent), and an open transaction's copy for one
        /// it has changed (see mTransactions)
        pub fn GetComponent(self: Self, comptime component_type: type, entity_id: entity_t) ?*const component_type {
            _ValidateType(component_type);
            std.debug.assert(self.IsActiveEntity(entity_id));
            if (self._Measuring()) |transaction| self._NoteRead(transaction, ComponentInd(component_type), entity_id);
            if (comptime _Copies(component_type)) {
                if (self._OpenTransaction()) |transaction| {
                    if (transaction.Find(self._TransactionKey(component_type, entity_id))) |copy| return @ptrCast(@alignCast(copy));
                }
            }
            return self._FindComponent(component_type, entity_id);
        }

        /// GetComponent for changing it. While a transaction is open, the change is made to its copy (see mTransactions),
        /// which this makes the first time. Failing to make it is out of memory, which panics like any other.
        pub fn GetComponentMut(self: Self, comptime component_type: type, entity_id: entity_t) ?*component_type {
            _ValidateType(component_type);
            std.debug.assert(self.IsActiveEntity(entity_id));
            //handed out to change counts as changed, whether or not it is: the copy is made either way
            if (self._Measuring()) |transaction| {
                self._NoteRead(transaction, ComponentInd(component_type), entity_id);
                transaction.NoteValueWrite(self._KeyInd(ComponentInd(component_type), entity_id), ComponentNames[ComponentInd(component_type)]);
            }
            if (comptime _Copies(component_type)) {
                if (self._OpenTransaction()) |transaction| return self._CopyInto(transaction, component_type, entity_id);
            }
            return self._FindComponent(component_type, entity_id);
        }

        // the transaction's copy of the component, made now if it hasn't been. A component staged during the run isn't
        // copied: it isn't in storage yet, and is handed out as it is
        fn _CopyInto(self: Self, transaction: *Transaction, comptime component_type: type, entity_id: entity_t) ?*component_type {
            const key = self._TransactionKey(component_type, entity_id);
            if (transaction.Find(key)) |copy| return @ptrCast(@alignCast(copy));
            // one this transaction added is its own already
            if (transaction.Presence(key)) |held| {
                if (held.mKind == .Add) return @ptrCast(@alignCast(held.mData.?));
            }
            const component = self.mComponentManager.GetComponent(component_type, entity_id) orelse return self._FindComponent(component_type, entity_id);
            const fns = self.mComponentManager.mComponentsArrays.items[ComponentInd(component_type)].CopyFns();
            const copy = transaction.Copy(key, component, fns) catch |err| {
                // a Clone that does something a speculating hook mustn't (makes a UI element): the hook is run again on
                // its own, and what it does until it ends is thrown away, so it is handed nothing meanwhile
                if (transaction.mRunSerially) return null;
                std.debug.panic("Copying {s} into a transaction: {s}", .{ @typeName(component_type), @errorName(err) });
            };
            return @ptrCast(@alignCast(copy));
        }

        fn _TransactionKey(self: Self, comptime component_type: type, entity_id: entity_t) Transaction.Key {
            return .{ .mArray = self.mComponentManager.ArrayOf(component_type), .mEntityID = entity_id };
        }

        // the component the open transaction holds added, or on the entity, or its staged copy. Null for a tag the
        // transaction holds taken off
        fn _FindComponent(self: Self, comptime component_type: type, entity_id: entity_t) ?*component_type {
            if (self._HeldPresence(ComponentInd(component_type), entity_id)) |op| {
                if (op.mKind == .Add) return @ptrCast(@alignCast(op.mData.?));
                return if (op.mOn) _NoValue(component_type) else null;
            }
            if (self.mComponentManager.GetComponent(component_type, entity_id)) |component| return component;
            const staged = self._GetStaged(entity_id, ComponentInd(component_type)) orelse return null;
            return @ptrCast(@alignCast(staged));
        }
        /// Replaces a component with a new value, deinitializing the old one.
        pub fn ResetComponent(self: *Self, engine_context: *EngineContext, entity_id: entity_t, component: anytype) void {
            const zone = Tracy.ZoneInit(debug_name ++ "::ResetComponent", @src());
            defer zone.Deinit();
            _ValidateType(@TypeOf(component));

            std.debug.assert(self.IsActiveEntity(entity_id));

            self.mComponentManager.ResetComponent(engine_context, entity_id, component);
        }

        /// Drains whatever is queued (see mRunDepth). Nothing normally is by now: the queue drains when the last run ends,
        /// and every run has to have ended before this
        pub fn ProcessEvents(self: *Self, engine_context: *EngineContext) !void {
            std.debug.assert(!self._InRun());
            if (self._HasQueued()) try self._Drain(engine_context);
        }

        // makes every queued change, in the order they were asked for, then empties the queue and the staging arena.
        // What the changes set off goes to the end of the queue while it drains, and is made in this same pass
        fn _Drain(self: *Self, engine_context: *EngineContext) !void {
            const zone = Tracy.ZoneInit(debug_name ++ "::Drain", @src());
            defer zone.Deinit();

            const queue = self.mECSEventManager.mEventsArray.getPtr(.EndOfFrame);
            var event_ind: usize = 0;
            // indexed, not sliced: draining appends to the queue
            while (event_ind < queue.items.len) : (event_ind += 1) {
                switch (queue.items[event_ind]) {
                    .AddComponent => |e| try self._InternalAddComponent(engine_context, e.mEntityID, e.mComponentInd, e.mData),
                    .RemoveComponent => |e| if (self.IsActiveEntity(e.mEntityID)) try self._RemoveNow(engine_context, e.mEntityID, e.mComponentInd),
                    .DestroyEntity => |e| try self._DestroyNow(engine_context, e.mEntityID),
                    .Default => unreachable,
                }
            }
            zone.Value(event_ind);

            self.mECSEventManager.ClearCategory(engine_context.EngineAllocator(), .EndOfFrame, .ClearRetainingCapacity);
            // every staged component has now been copied onto its entity or deinitialized with it
            std.debug.assert(self.mStaged.count() == 0);
            self._ResetStagingArena(engine_context.EngineAllocator());
        }

        /// Applies a queued AddComponent. One taken back off the stage (RemoveComponentSync) is skipped, its
        /// component already deinitialized. An entity destroyed earlier in the same pass takes its staged components
        /// with it, so they are deinitialized here instead.
        fn _InternalAddComponent(self: *Self, engine_context: *EngineContext, entity_id: entity_t, component_ind: usize, staged: *anyopaque) !void {
            // compared by pointer as well: after a removal the same component can be staged again, under the same key
            const key = StagedKey{ .mEntityID = entity_id, .mComponentInd = component_ind };
            if (self.mStaged.get(key) != staged) return;
            _ = self.mStaged.remove(key);

            if (!self.IsActiveEntity(entity_id)) {
                self.mComponentManager.DeinitStaged(engine_context, component_ind, staged);
                return;
            }

            const zone = Tracy.ZoneInit(debug_name ++ "::_InternalAddComponent", @src());
            defer zone.Deinit();

            try self.mComponentManager.AddStaged(engine_context.EngineAllocator(), entity_id, component_ind, staged);
        }

        // deinitializes every component still staged, for when the queue is dropped unprocessed
        fn _DeinitStagedAdds(self: *Self, engine_context: *EngineContext) void {
            var iter = self.mStaged.iterator();
            while (iter.next()) |entry| {
                self.mComponentManager.DeinitStaged(engine_context, entry.key_ptr.mComponentInd, entry.value_ptr.*);
            }
            self.mStaged.clearRetainingCapacity();
        }

        // gives each queued add copied over from `source` a clone of its own in this ECS's staging arena, listed in
        // mStaged like any other. An add that source no longer has staged keeps pointing into source's arena, but
        // isn't listed here, so it is skipped and never read. On failure the clones made so far are listed, which is
        // all Copy's clearAndFree needs to free them
        fn _CloneCopiedAdds(self: *Self, engine_context: *EngineContext, source: *const Self) !void {
            const engine_allocator = engine_context.EngineAllocator();
            var staging_arena = self.mStagingArena.promote(engine_allocator);
            defer self.mStagingArena = staging_arena.state;

            for (self.mECSEventManager.mEventsArray.getPtr(.EndOfFrame).items) |*event| switch (event.*) {
                .AddComponent => |*add| {
                    if (source._GetStaged(add.mEntityID, add.mComponentInd) != add.mData) continue;
                    add.mData = try self.mComponentManager.CloneStaged(engine_context, staging_arena.allocator(), add.mComponentInd, add.mData);
                    errdefer self.mComponentManager.DeinitStaged(engine_context, add.mComponentInd, add.mData);
                    try self.mStaged.put(engine_allocator, .{ .mEntityID = add.mEntityID, .mComponentInd = add.mComponentInd }, add.mData);
                },
                else => {},
            };
        }

        fn _ResetStagingArena(self: *Self, engine_allocator: std.mem.Allocator) void {
            var staging_arena = self.mStagingArena.promote(engine_allocator);
            _ = staging_arena.reset(.retain_capacity);
            self.mStagingArena = staging_arena.state;
        }

        // the destroy itself, of the entity and everything under it: children first, so each one leaves a parent that is
        // still there, and the hook hears of each just before it goes. Nothing for one that is gone already
        fn _DestroyNow(self: *Self, engine_context: *EngineContext, entity_id: entity_t) anyerror!void {
            if (!self.IsActiveEntity(entity_id)) return;
            self._CheckMainThread("Destroying an object");

            const zone = Tracy.ZoneInit(debug_name ++ "::DestroyEntity", @src());
            defer zone.Deinit();

            try self._DestroyChildrenNow(engine_context, entity_id, .Entity);
            try self._DestroyChildrenNow(engine_context, entity_id, .Script);

            try self._CallRemovalHook(engine_context, .{ .DestroyEntity = .{ .mEntityID = entity_id } });
            // the hook may have destroyed it itself
            if (!self.IsActiveEntity(entity_id)) return;

            try self._InternalRemoveFromHierarchy(engine_context, entity_id);
            self.mComponentManager.DestroyEntity(engine_context, entity_id);
        }

        // destroys one of the entity's two child lists, always its first child: each destroy unlinks the child it was,
        // and the ParentComponent goes with the last one
        fn _DestroyChildrenNow(self: *Self, engine_context: *EngineContext, entity_id: entity_t, child_type: ChildType) anyerror!void {
            while (self.mComponentManager.GetComponent(ParentComponent, entity_id)) |parent_component| {
                const first_id = switch (child_type) {
                    .Entity => parent_component.mFirstEntity,
                    .Script => parent_component.mFirstScript,
                };
                if (first_id == std.math.maxInt(entity_t)) return;
                try self._DestroyNow(engine_context, first_id);
            }
        }

        // takes this entity out of its parent's child or script list, leaving that list valid
        fn _InternalRemoveFromHierarchy(self: *Self, engine_context: *EngineContext, entity_id: entity_t) anyerror!void {
            std.debug.assert(self.IsActiveEntity(entity_id));
            const child_component = self.GetComponent(ChildComponent, entity_id) orelse return;

            const parent_entity: entity_t = child_component.mParent;
            // the parent goes first when a whole subtree is destroyed, so there may be no list left to leave
            if (!self.IsActiveEntity(parent_entity)) return;

            const parent_component = self.GetComponentMut(ParentComponent, parent_entity) orelse return;

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
                const next_comp = self.GetComponentMut(ChildComponent, next_id).?;
                const prev_comp = self.GetComponentMut(ChildComponent, prev_id).?;
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
                self._CheckStorageChange(ParentComponent.Ind, "Removing");
                self.mComponentManager.RemoveComponent(engine_context, parent_entity, ParentComponent.Ind);
            }
        }

        // every child carries the head of its list in mFirst, so moving the head updates all of them
        fn _InternalSetListFirst(self: *Self, first_id: entity_t) void {
            var curr_id = first_id;
            while (true) {
                const curr_component = self.GetComponentMut(ChildComponent, curr_id).?;
                curr_component.mFirst = first_id;

                curr_id = curr_component.mNext;
                if (curr_id == first_id) break; // the list is circular
            }
        }

        fn _ValidateCompList(comptime component_list: []const type) void {
            inline for (component_list) |component_type| {
                //concatenated rather than comptimePrint: formatting costs compile time steps per character, and with
                //enough components the list ran past the default limit
                const type_name = " " ++ @typeName(component_type);
                const type_info = @typeInfo(component_type);
                switch (type_info) {
                    .@"struct" => {},
                    else => @compileError(type_name ++ "component must be a struct!"),
                }

                if (!@hasDecl(component_type, "Name")) {
                    @compileError(type_name ++ "Type needs 'Name' pub const declaration ");
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
                    if (return_type != void) {
                        @compileError(type_name ++ "'s Deinit must return void, currently " ++ @typeName(return_type));
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
            const type_name = " " ++ @typeName(component_type) ++ "\n";

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
