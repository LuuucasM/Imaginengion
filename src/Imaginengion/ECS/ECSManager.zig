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

/// A run of a system through the systems layer (Systems.RunSystem), while it goes on: which system, and the run it is
/// inside of. Each record the run puts on an ECS names it, so the debug checks can tell an ECS the run was given from
/// one it wasn't
pub const RunInfo = struct {
    mName: [:0]const u8,
    mOuter: ?*const RunInfo,
};

/// The level the debug checks report a mistake at. An error by default, which also fails a test that runs into one
/// (Zig's test runner fails any test that logs an error); a test that makes a mistake on purpose lowers it to warn
pub var access_report_level: std.log.Level = .err;

// what the debug checks have reported, so a mistake in a loop is reported once and not on every pass: a hash of who
// made it, in which kind of ECS, and what. Once every slot is used everything is reported
var reported_keys: [64]u64 = undefined;
var reported_count: usize = 0;

/// How many different mistakes the debug checks have reported so far, for tests
pub fn ReportedCount() usize {
    return reported_count;
}

// reports a debug check's mistake, unless the same one was reported before
fn _Report(who: []const u8, where: []const u8, what: u64, comptime format: []const u8, args: anytype) void {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(who);
    hasher.update(where);
    hasher.update(std.mem.asBytes(&what));
    const key = hasher.final();
    for (reported_keys[0..reported_count]) |reported_key| {
        if (reported_key == key) return;
    }
    if (reported_count < reported_keys.len) {
        reported_keys[reported_count] = key;
        reported_count += 1;
    }
    switch (access_report_level) {
        .err => std.log.err(format, args),
        .warn => std.log.warn(format, args),
        .info => std.log.info(format, args),
        .debug => std.log.debug(format, args),
    }
}

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
        /// The name this ECS type was made with, which the systems layer tells kinds of ECS apart by (Systems.KindId)
        pub const DebugName = debug_name;
        pub const ECSCallbackList = ECSEventManager.CallbackList;
        pub const ECSEventCallback = ECSEventManager.EventCallback;
        const Self = @This();

        pub const empty: Self = .{
            .mNextID = 0,
            .mComponentManager = .empty,
            .mECSEventManager = .empty,
            .mStagingArena = .init,
            .mStaged = .empty,
            .mLockCounts = @splat(0),
            .mLockTotal = 0,
            .mRemovalHook = null,
            .mCurrentSystem = null,
            .mRunMarker = null,
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
        /// How many times each component's storage is locked (see Lock), by ComponentInd
        mLockCounts: [components_types.len + BuiltinComponentCount]u16,
        /// Every lock in mLockCounts added up: the queue drains when this gets back to 0
        mLockTotal: u32,
        mRemovalHook: ?RemovalHook,
        /// The innermost system running on this ECS (see SystemRecord), for the debug checks
        mCurrentSystem: ?*const SystemRecord,
        /// Where the systems layer this ECS is registered with keeps the run going on now (see Systems.Register), for
        /// the debug check that a run only touches the ECSs it was given. Null outside any layer
        mRunMarker: ?*const ?*const RunInfo,

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

        // returns an active id that has only its SkipFieldComponent, reusing a destroyed id when there is one
        fn _CreateID(self: *Self, engine_allocator: std.mem.Allocator) !entity_t {
            if (self.mComponentManager.ReuseFreeEntity()) |reused_id| return reused_id;

            const new_entity_id = self.mNextID;
            std.debug.assert(!self.IsActiveEntity(new_entity_id));

            try self.mComponentManager.CreateNewEntity(engine_allocator, new_entity_id);
            self.mNextID += 1; // only consume the id once it has actually been created

            return new_entity_id;
        }

        /// Destroys the entity and everything under it, its children and scripts, right away. Queued instead (see
        /// Lock) when any of them has a component whose type is locked, or something is queued already.
        pub fn DestroyEntity(self: *Self, engine_context: *EngineContext, entity_id: entity_t) !void {
            std.debug.assert(self.IsActiveEntity(entity_id));
            if (self._HasQueued() or self._SubtreeLocked(entity_id)) {
                try self.mECSEventManager.Insert(engine_context.EngineAllocator(), .EndOfFrame, .{ .DestroyEntity = .{ .mEntityID = entity_id } });
                return;
            }
            try self._DestroyNow(engine_context, entity_id);
        }

        /// Every active entity, because they all carry a SkipFieldComponent.
        pub fn GetAllEntities(self: Self, allocator: std.mem.Allocator) !std.ArrayList(entity_t) {
            return try self.GetGroup(allocator, .{ .Component = SkipFieldComponent });
        }

        /// Copies an entity along with its children and scripts, the components staged on them included. The copies
        /// are made now, and their components added the way AddComponent adds them: staged for a locked type, right
        /// away for anything else.
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
            if (self.mComponentManager.IsTag(component_ind) or !self._Queues(component_ind)) {
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
            return self.mComponentManager.NumWithComponent(component_type);
        }

        /// Every `component_type` in this ECS, for a pass over all of them that has no use for the
        /// ids. Only good until a component of that type is added or removed.
        pub fn GetComponentSlice(self: Self, comptime component_type: type) []const component_type {
            _ValidateType(component_type);
            self._CheckAccess(component_type, false);
            return self.mComponentManager.GetComponentSlice(component_type);
        }

        /// GetComponentSlice for changing them: a running system has to list `component_type` in its Writes
        pub fn GetComponentSliceMut(self: Self, comptime component_type: type) []component_type {
            _ValidateType(component_type);
            self._CheckAccess(component_type, true);
            return self.mComponentManager.GetComponentSlice(component_type);
        }

        //for getting groups of entities
        pub fn GetGroup(self: Self, allocator: std.mem.Allocator, comptime query: GroupQuery) !std.ArrayList(entity_t) {
            _ValidateGroupQuery(query);
            const zone = Tracy.ZoneInit(debug_name ++ "::GetGroup", @src());
            defer zone.Deinit();
            self._CheckQuery(query);

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

        //--------systems----------
        /// Each component's slot is set when a running system may get pointers into it
        pub const AllowedSet = std.bit_set.StaticBitSet(components_types.len + BuiltinComponentCount);

        /// What a run of a system (Systems.RunSystem) keeps on its own stack on this ECS, so the debug checks know what it
        /// listed. Chained: the innermost one is what is checked, a system inside another can't lean on what the outer
        /// one listed
        pub const SystemRecord = struct {
            mName: [:0]const u8,
            /// what it listed at all, in its Reads or its Writes
            mAllowed: AllowedSet,
            /// what it listed in its Writes, which it may get mutable pointers into (GetComponentMut)
            mWritable: AllowedSet,
            /// for engine code that runs inside a system without being its work (see UncheckedRecord)
            mUnchecked: bool = false,
            /// the systems layer's run that put it here; null for one put here some other way, which counts as a run of
            /// its own
            mRun: ?*const RunInfo = null,
            mOuter: ?*const SystemRecord = null,
        };

        /// A record for engine code that runs inside a system without being the system's own work: the bookkeeping
        /// adding, removing, creating and deleting set off, and code run on others' behalf (scripts). Nothing it touches
        /// is charged to the system around it
        pub const UncheckedRecord: SystemRecord = .{ .mName = "(unchecked)", .mAllowed = .empty, .mWritable = .empty, .mUnchecked = true };

        /// The record for a system that reads `reads` and writes `writes`. A type may be in both
        pub fn SystemRecordFor(comptime name: [:0]const u8, comptime reads: []const type, comptime writes: []const type) SystemRecord {
            const sets = comptime blk: {
                //each type looked up in the whole component list
                @setEvalBranchQuota(100_000);
                var allowed: AllowedSet = .empty;
                var writable: AllowedSet = .empty;
                for (reads) |listed_type| allowed.set(ComponentInd(listed_type));
                for (writes) |listed_type| {
                    allowed.set(ComponentInd(listed_type));
                    writable.set(ComponentInd(listed_type));
                }
                break :blk .{ allowed, writable };
            };
            return .{ .mName = name, .mAllowed = sets[0], .mWritable = sets[1] };
        }

        /// Makes `record` the innermost one until LeaveSystem. It lives on the caller's stack
        pub fn EnterSystem(self: *Self, record: *SystemRecord) void {
            record.mOuter = self.mCurrentSystem;
            self.mCurrentSystem = record;
        }

        pub fn LeaveSystem(self: *Self, record: *const SystemRecord) void {
            std.debug.assert(self.mCurrentSystem == record);
            self.mCurrentSystem = record.mOuter;
        }

        /// Points this ECS at where a systems layer keeps its current run (null to stop), see mRunMarker
        pub fn SetRunMarker(self: *Self, marker: ?*const ?*const RunInfo) void {
            self.mRunMarker = marker;
        }

        /// Whether the system running now may get pointers into `component_type`: one it listed, or anything outside a
        /// system or inside an unchecked record. Tags (nothing to point into) and the hierarchy components (read by
        /// engine helpers everywhere) are always allowed
        pub fn AllowsAccess(self: Self, comptime component_type: type) bool {
            if (comptime @sizeOf(component_type) == 0) return true;
            if (comptime component_type == ParentComponent or component_type == ChildComponent or component_type == SkipFieldComponent) return true;
            const record = self.mCurrentSystem orelse return true;
            if (record.mUnchecked) return true;
            return record.mAllowed.isSet(ComponentInd(component_type));
        }

        /// Whether the system running now may get mutable pointers into `component_type` (GetComponentMut): one it
        /// listed in its Writes, and the same exceptions as AllowsAccess
        pub fn AllowsWrite(self: Self, comptime component_type: type) bool {
            if (comptime @sizeOf(component_type) == 0) return true;
            if (comptime component_type == ParentComponent or component_type == ChildComponent or component_type == SkipFieldComponent) return true;
            const record = self.mCurrentSystem orelse return true;
            if (record.mUnchecked) return true;
            return record.mWritable.isSet(ComponentInd(component_type));
        }

        /// Whether an add or removal can go straight to this component's storage: a tag has none to move, and anything
        /// else only when it isn't locked
        pub fn CanChangeStorage(self: Self, component_ind: usize) bool {
            return self.mComponentManager.IsTag(component_ind) or self.mLockCounts[component_ind] == 0;
        }

        // in safe builds, reports (once) a running system using this ECS when it wasn't given it, using a component it
        // didn't list, or asking to change (`write`) one it only listed in its Reads. Logged rather than stopping: the
        // mistake is in a list, and what it touches is still there
        fn _CheckAccess(self: Self, comptime component_type: type, comptime write: bool) void {
            if (!std.debug.runtime_safety) return;
            if (self._RunNotGiven()) |run| {
                _Report(run.mName, debug_name, std.math.maxInt(u64), "{s} used a " ++ debug_name ++ " it wasn't given: not the ECS it was run from, nor one connected to it through an In", .{run.mName});
                return;
            }
            if (!self.AllowsAccess(component_type)) {
                const name = self.mCurrentSystem.?.mName;
                _Report(name, debug_name, ComponentInd(component_type), "{s} used {s} without listing it in its Reads or Writes", .{ name, @typeName(component_type) });
                return;
            }
            if (write and !self.AllowsWrite(component_type)) {
                const name = self.mCurrentSystem.?.mName;
                _Report(name, debug_name, (1 << 32) | ComponentInd(component_type), "{s} asked to change {s} (GetComponentMut) but only lists it in its Reads", .{ name, @typeName(component_type) });
            }
        }

        // GetGroup's query read as access: every component in it, kept and left out alike, since the ids it hands back
        // are only good while those don't change
        fn _CheckQuery(self: Self, comptime query: GroupQuery) void {
            switch (query) {
                .Component => |component_type| self._CheckAccess(component_type, false),
                .And, .Or => |queries| inline for (queries) |sub_query| self._CheckQuery(sub_query),
                .Not => |not| {
                    self._CheckQuery(not.mFirst.*);
                    self._CheckQuery(not.mSecond.*);
                },
            }
        }

        // the systems layer's run going on now, when this ECS isn't part of it: no record here, or only one put here by
        // a run outside it. A record put here some other way (not by the layer) is a run of its own, and checked by its list
        fn _RunNotGiven(self: Self) ?*const RunInfo {
            const marker = self.mRunMarker orelse return null;
            const run = marker.* orelse return null;
            const record = self.mCurrentSystem orelse return run;
            if (record.mUnchecked) return null;
            const record_run = record.mRun orelse return null;
            return if (record_run == run) null else run;
        }

        // in safe builds, a panic when a change reaches storage that is locked: it would move what a running system holds
        fn _CheckStorageChange(self: Self, component_ind: usize, comptime change: []const u8) void {
            if (!std.debug.runtime_safety) return;
            if (self.CanChangeStorage(component_ind)) return;
            std.debug.panic(change ++ " {s} while it is locked, which would move what a running system holds", .{ComponentNames[component_ind]});
        }

        // each slot's component type name, for the debug checks' messages
        const ComponentNames = blk: {
            var names: [components_types.len + BuiltinComponentCount][]const u8 = undefined;
            for ([_]type{ ParentComponent, ChildComponent, SkipFieldComponent, MainObjectComponent, EntityTagComponent, ScriptTagComponent }) |builtin_type| {
                names[ComponentInd(builtin_type)] = @typeName(builtin_type);
            }
            for (components_types, 0..) |listed_type, listed_ind| names[listed_ind + BuiltinComponentCount] = @typeName(listed_type);
            break :blk names;
        };

        /// Whether `component_type` is one of this ECS's components, the builtin ones included
        pub fn HasType(comptime component_type: type) bool {
            if (component_type == ParentComponent or component_type == ChildComponent or component_type == SkipFieldComponent or
                component_type == MainObjectComponent or component_type == EntityTagComponent or component_type == ScriptTagComponent) return true;
            inline for (components_types) |listed_type| {
                if (listed_type == component_type) return true;
            }
            return false;
        }

        //--------components related functions----------
        /// Holds off structural changes to these components' storage until the matching Unlock, for code that keeps
        /// pointers, slices or lists of ids into it while something it calls might change it. Adds, removals and
        /// destroys are made right away, except that while a type is locked:
        ///   - adding one is staged (see AddComponent)
        ///   - removing one is queued
        ///   - destroying an entity that has one, itself or anywhere under it, is queued
        /// Once anything is queued everything after it is queued as well, whatever its type, so changes always land
        /// in the order they were asked for. The queue drains, in that order, when the last lock in this ECS is let go
        /// of. Tags are the exception: with no storage to move they are always added and removed right away.
        /// Counted per type, so locks nest.
        pub fn Lock(self: *Self, comptime locked_types: []const type) void {
            inline for (locked_types) |locked_type| {
                _ValidateType(locked_type);
                self.mLockCounts[ComponentInd(locked_type)] += 1;
                self.mLockTotal += 1;
            }
        }

        /// Lets go of what Lock took, and drains the queue when that was the last lock in this ECS
        pub fn Unlock(self: *Self, engine_context: *EngineContext, comptime locked_types: []const type) !void {
            inline for (locked_types) |locked_type| {
                _ValidateType(locked_type);
                std.debug.assert(self.mLockCounts[ComponentInd(locked_type)] > 0);
                self.mLockCounts[ComponentInd(locked_type)] -= 1;
                self.mLockTotal -= 1;
            }
            if (self.mLockTotal == 0 and self._HasQueued()) try self._Drain(engine_context);
        }

        // whether a change to this slot waits in the queue: its type is locked, or something is queued already
        fn _Queues(self: Self, component_ind: usize) bool {
            return self.mLockCounts[component_ind] > 0 or self._HasQueued();
        }

        fn _HasQueued(self: Self) bool {
            return self.mECSEventManager.mEventsArray.get(.EndOfFrame).items.len > 0;
        }

        // whether the entity or anything under it has a component whose type is locked
        fn _SubtreeLocked(self: *Self, entity_id: entity_t) bool {
            if (self.mLockTotal == 0) return false;

            var skipfield = self.mComponentManager.GetComponent(SkipFieldComponent, entity_id).?.mSkipField;
            var field_iter = skipfield.Iterator();
            while (field_iter.next()) |component_ind| {
                if (self.mLockCounts[component_ind] > 0) return true;
            }

            const parent_component = self.mComponentManager.GetComponent(ParentComponent, entity_id) orelse return false;
            for ([_]entity_t{ parent_component.mFirstEntity, parent_component.mFirstScript }) |first_id| {
                if (first_id == std.math.maxInt(entity_t)) continue;
                var curr_id = first_id;
                while (true) {
                    if (self._SubtreeLocked(curr_id)) return true;
                    curr_id = self.mComponentManager.GetComponent(ChildComponent, curr_id).?.mNext;
                    if (curr_id == first_id) break; // the list is circular
                }
            }
            return false;
        }

        /// Adds the component now, unless it has to wait (see Lock). Then it is staged instead: its storage only takes
        /// it when the queue drains, so no component already in that array moves while it is locked. Until then
        /// GetComponent and HasComponent find the staged copy, which is also what this returns, so the entity reads as
        /// having it straight away; queries (GetGroup, GetComponentSlice, NumWithComponent) only see it once it lands.
        /// A tag has no storage that could move, so it always goes on right away.
        pub fn AddComponent(self: *Self, engine_context: *EngineContext, entity_id: entity_t, new_component: anytype) !*@TypeOf(new_component) {
            const component_t = @TypeOf(new_component);
            if (comptime @sizeOf(component_t) == 0) return try self.AddComponentSync(engine_context, entity_id, new_component);
            if (!self._Queues(ComponentInd(component_t))) return try self.AddComponentSync(engine_context, entity_id, new_component);

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

        // lists a component already in the staging arena under its entity and queues its add
        fn _QueueStagedAdd(self: *Self, engine_allocator: std.mem.Allocator, entity_id: entity_t, component_ind: usize, staged_component: *anyopaque) !void {
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

        /// Removes the component right away, unless it has to wait (see Lock), when the removal is queued and the
        /// component stays readable until the queue drains. A tag always comes off right away.
        pub fn RemoveComponent(self: *Self, engine_context: *EngineContext, entity_id: entity_t, component_ind: usize) !void {
            std.debug.assert(self.IsActiveEntity(entity_id));
            std.debug.assert(components_types.len + BuiltinComponentCount > component_ind);
            std.debug.assert(component_ind != SkipFieldComponent.Ind); // entity lifetime goes through DestroyEntity
            if (self.mComponentManager.IsTag(component_ind) or !self._Queues(component_ind)) return try self._RemoveNow(engine_context, entity_id, component_ind);
            try self.mECSEventManager.Insert(engine_context.EngineAllocator(), .EndOfFrame, .{ .RemoveComponent = .{ .mEntityID = entity_id, .mComponentInd = component_ind } });
        }

        /// RemoveComponent made right away even while the type is locked. Only where nothing holds a pointer into that
        /// component's storage: the removal swapRemoves from the dense array, which moves another entity's component.
        pub fn RemoveComponentSync(self: *Self, engine_context: *EngineContext, entity_id: entity_t, component_ind: usize) !void {
            std.debug.assert(self.IsActiveEntity(entity_id));
            std.debug.assert(components_types.len + BuiltinComponentCount > component_ind);
            std.debug.assert(component_ind != SkipFieldComponent.Ind); // entity lifetime goes through DestroyEntity
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

        // the hook is bookkeeping, not the work of a system it might run inside, so it runs unchecked
        fn _CallRemovalHook(self: *Self, engine_context: *EngineContext, event: ECSEventDataT.EventT) !void {
            const hook = self.mRemovalHook orelse return;
            var record = UncheckedRecord;
            self.EnterSystem(&record);
            defer self.LeaveSystem(&record);
            try hook.mFn(hook.mCtx, engine_context, event);
        }

        /// True for a component that is staged as well (see AddComponent)
        pub fn HasComponent(self: Self, comptime ComponentType: type, entity_id: entity_t) bool {
            _ValidateType(ComponentType);
            std.debug.assert(self.IsActiveEntity(entity_id));
            return self.mComponentManager.HasComponent(ComponentType, entity_id) or
                self._GetStaged(entity_id, ComponentInd(ComponentType)) != null;
        }

        /// HasComponent for a component known only by its slot (ComponentInd) at runtime
        pub fn HasComponentInd(self: Self, component_ind: usize, entity_id: entity_t) bool {
            std.debug.assert(self.IsActiveEntity(entity_id));
            return self.mComponentManager.HasComponentInd(component_ind, entity_id) or
                self._GetStaged(entity_id, component_ind) != null;
        }

        /// The staged copy for a component that is still staged (see AddComponent)
        pub fn GetComponent(self: Self, comptime component_type: type, entity_id: entity_t) ?*const component_type {
            _ValidateType(component_type);
            std.debug.assert(self.IsActiveEntity(entity_id));
            self._CheckAccess(component_type, false);
            return self._FindComponent(component_type, entity_id);
        }

        /// GetComponent for changing it: a running system has to list `component_type` in its Writes
        pub fn GetComponentMut(self: Self, comptime component_type: type, entity_id: entity_t) ?*component_type {
            _ValidateType(component_type);
            std.debug.assert(self.IsActiveEntity(entity_id));
            self._CheckAccess(component_type, true);
            return self._FindComponent(component_type, entity_id);
        }

        /// The component just added to the entity, for what adds it to hand back (Manager.AddComponent fetches it
        /// again after the bookkeeping the add sets off). Mutable and not checked: what was added is the adder's
        pub fn GetAddedComponent(self: Self, comptime component_type: type, entity_id: entity_t) ?*component_type {
            _ValidateType(component_type);
            std.debug.assert(self.IsActiveEntity(entity_id));
            return self._FindComponent(component_type, entity_id);
        }

        // the component on the entity, or its staged copy
        fn _FindComponent(self: Self, comptime component_type: type, entity_id: entity_t) ?*component_type {
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

        /// Drains whatever is queued (see Lock). Nothing normally is by now: the queue drains when the last lock is let
        /// go of, and every lock has to be let go of before this
        pub fn ProcessEvents(self: *Self, engine_context: *EngineContext) !void {
            std.debug.assert(self.mLockTotal == 0);
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
