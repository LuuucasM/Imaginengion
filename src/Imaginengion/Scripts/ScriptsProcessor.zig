//! This file exists as a location to group together all the functions that run
//! scripts rather than cluddering up other engine files like scene manager or something
//!
//! A script is a child object of the thing it belongs to: it carries a ScriptComponent
//! holding the asset handle and a tag component saying when it runs. That shape is the
//! same for entities, scenes, players and game contexts, so RunScript covers all four.
const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const WorldManager = @import("../Core/WorldManager.zig");
const GroupQuery = @import("../ECS/ECSManager.zig").GroupQuery;

const Entity = @import("../ECSObjects/Entity.zig");
const GameContext = @import("../ECSObjects/GameContext.zig");
const Player = @import("../ECSObjects/Player.zig");
const Scene = @import("../ECSObjects/Scene.zig");

const EComponents = @import("../ECSComponents/EComponents.zig");
const GCComponents = @import("../ECSComponents/GCComponents.zig");
const PComponents = @import("../ECSComponents/PComponents.zig");
const SComponents = @import("../ECSComponents/SComponents.zig");

const ScriptComponent = @import("../ECSComponents/Shared/ScriptComponent.zig");
const ChildComponent = @import("../ECS/Components.zig").ChildComponent;
const EntitySceneComponent = EComponents.EntitySceneComponent;
const StackPosComponent = SComponents.StackPosComponent;
const OnCollisionBeginScript = EComponents.OnCollisionBeginScript;
const OnCollisionEndScript = EComponents.OnCollisionEndScript;
const OnPreSolveScript = EComponents.OnPreSolveScript;
const OnPointerEventScript = EComponents.OnPointerEventScript;
const OnUIEventScript = EComponents.OnUIEventScript;
const UntypedScriptTag = @import("../ECSComponents/Shared/ScriptTags.zig").UntypedScriptTag;
const GameEventScript = @import("../ECSComponents/Shared/ScriptTags.zig").GameEventScript;
const GameEvents = @import("GameEvents.zig");
const GamePhase = GameEvents.GamePhase;
const EntityPointerEvent = @import("../Events/PointerEventData.zig").EntityEvent;
const EntityUIEvent = @import("../Events/UIEventData.zig").EntityEvent;

const CollisionInfo = @import("../Physics/Collisions.zig").CollisionInfo;
const CollisionBeginEvent = @import("../Events/PhysicsEventData.zig").CollisionBeginEvent;
const CollisionEndEvent = @import("../Events/PhysicsEventData.zig").CollisionEndEvent;
const PreSolveEvent = @import("../Events/PhysicsEventData.zig").PreSolveEvent;
const PhysicsEventData = @import("../Events/PhysicsEventData.zig");
const PhysicsEvent = PhysicsEventData.EventT;
const EventResult = @import("../Events/EventManager.zig").EventResult;
const PreSolveInfo = @import("../Physics/Collisions.zig").PreSolveInfo;

const Assets = @import("../ECSComponents/AComponents.zig");
const ScriptAsset = Assets.ScriptAsset;
const ScriptABI = @import("ScriptABI.zig");
const ScriptValues = @import("ScriptValues.zig");
pub const ScriptResult = ScriptABI.ScriptResult;
const AssetHandle = @import("../ECSObjects/AssetHandle.zig");

const Tracy = @import("../Core/Tracy.zig");

/// Runs every script of the given tag type belonging to objects of ObjectType, in scene stack order, and stops early
/// if a script says it handled what it ran for. Handled if one did
pub fn RunScript(
    comptime ObjectType: type,
    comptime script_type: type,
    comptime world_type: EngineContext.WorldType,
    engine_context: *EngineContext,
    args: anytype,
) !ScriptResult {
    return RunScriptsFrom(ObjectType, script_type, WorldOf(world_type, engine_context), @tagName(world_type), engine_context, null, args);
}

/// RunScript for a world given directly rather than by its type, for something that is handed the world it is
/// about (a physics step on that world)
pub fn RunScriptInWorld(
    comptime ObjectType: type,
    comptime script_type: type,
    world_manager: *WorldManager,
    engine_context: *EngineContext,
    args: anytype,
) !ScriptResult {
    return RunScriptsFrom(ObjectType, script_type, world_manager, "World", engine_context, null, args);
}

fn WorldOf(comptime world_type: EngineContext.WorldType, engine_context: *EngineContext) *WorldManager {
    return switch (world_type) {
        .Game => &engine_context.mGameWorld,
        .Editor => &engine_context.mEditorWorld,
        .Simulate => &engine_context.mSimulateWorld,
    };
}

/// RunScript for only the scenes above `stack_pos` in the scene stack: their turns come before that scene's. For an
/// event something in that scene takes at its own turn (a key a focused text field is typed with), so the scenes
/// under it never hear it. Handled if a script above dealt with the event, so it never reaches that scene
pub fn RunScriptAbove(
    comptime ObjectType: type,
    comptime script_type: type,
    comptime world_type: EngineContext.WorldType,
    engine_context: *EngineContext,
    stack_pos: usize,
    args: anytype,
) !ScriptResult {
    comptime std.debug.assert(ObjectType == Entity or ObjectType == Scene);
    return RunScriptsFrom(ObjectType, script_type, WorldOf(world_type, engine_context), @tagName(world_type), engine_context, stack_pos, args);
}

/// `above`: only scripts whose owner sits higher in the scene stack than this, null for all of them.
/// `world_name` is only for the profiler zone's name
fn RunScriptsFrom(
    comptime ObjectType: type,
    comptime script_type: type,
    world_manager: *WorldManager,
    comptime world_name: []const u8,
    engine_context: *EngineContext,
    above: ?usize,
    args: anytype,
) !ScriptResult {
    _ValidateScriptType(ObjectType, script_type);

    const zone = Tracy.ZoneInit("ScriptsProcessor::RunScript(" ++ Tracy.ShortTypeName(ObjectType) ++ ", " ++ Tracy.ShortTypeName(script_type) ++ ", " ++ world_name ++ ")", @src());
    defer zone.Deinit();

    const frame_allocator = engine_context.FrameAllocator();
    const manager = world_manager.GetManager(ObjectType);

    const script_ids = try manager.GetGroup(frame_allocator, GroupQuery{ .Component = script_type });
    SortByOwnerStackPos(ObjectType, world_manager, script_ids.items);

    for (script_ids.items) |script_id| {
        //sorted from the top of the stack down, so the rest are no higher
        if (above) |stack_pos| {
            if (OwnerStackPos(ObjectType, world_manager, OwnerOf(ObjectType, world_manager, script_id)) <= stack_pos) break;
        }

        const script_component = manager.GetComponent(ScriptComponent, script_id) orelse continue;
        const owner = ObjectType{ .mID = OwnerOf(ObjectType, world_manager, script_id), .mManager = world_manager };
        if (RunHook(ObjectType, script_type, engine_context, script_component, &owner, args) == .Handled) return .Handled;
    }

    return .Continue;
}

/// Runs the hook `script_type` stands for (its Hook) of one script child, whose ScriptComponent is `script_component`,
/// on `owner`. A script with nothing to run is skipped (.Continue): one that never loaded, one that is stopped (a file
/// it imports changed and it doesn't build), or one edited since it was tagged into one without the hook or for another
/// object type (retagged by SyncScripts)
fn RunHook(comptime ObjectType: type, comptime script_type: type, engine_context: *EngineContext, script_component: *const ScriptComponent, owner: *const ObjectType, args: anytype) ScriptResult {
    const id = script_component.mInstance orelse return .Continue;
    const script_asset = ScriptValues.AssetOf(script_component) orelse return .Continue;
    if (script_asset.mStopped) return .Continue;
    if (script_asset.GetOwner() != ScriptABI.OwnerKind.Of(ObjectType) or !script_asset.HasHook(script_type.Hook)) return .Continue;
    const instance = script_asset.GetInstance(id) orelse return .Continue;

    //one zone per script, renamed to the script's file so a slow script shows up by name
    const script_zone = Tracy.ZoneInit("ScriptsProcessor::Script", @src());
    defer script_zone.Deinit();
    if (Tracy.enable_tracy) script_zone.Name(script_component.mScriptAssetHandle.GetFileMetaData().mRelPath.items);

    return script_asset.RunHook(ObjectType, script_type.Hook, .{ engine_context, owner, instance } ++ args);
}

/// Runs the OnCollisionBegin scripts of both entities in a collision that has just begun. Meant for
/// after the physics step and never during it: a script is free to move or delete things, which the
/// step's contact lists could not survive.
pub fn RunCollisionBeginScripts(engine_context: *EngineContext, event: CollisionBeginEvent) !void {
    //each side is told about the contact as it sees it, so the normal always points at the other one
    try RunCollisionScripts(OnCollisionBeginScript, engine_context, event.mOrigin, event.mTarget, &CollisionInfo{
        .mNormal = event.mNormal,
        .mIsTrigger = event.mIsTrigger,
        .mSelfCollider = event.mOriginCollider,
        .mOtherCollider = event.mTargetCollider,
    });
    try RunCollisionScripts(OnCollisionBeginScript, engine_context, event.mTarget, event.mOrigin, &CollisionInfo{
        .mNormal = event.mNormal.Neg(),
        .mIsTrigger = event.mIsTrigger,
        .mSelfCollider = event.mTargetCollider,
        .mOtherCollider = event.mOriginCollider,
    });
}

/// Runs the OnCollisionEnd scripts of both entities in a collision that has just ended, after the physics step the
/// same as RunCollisionBeginScripts. A collision also ends when one side is deleted, so a side that is gone is
/// skipped and the other is still told: its script checks other.IsActive() before reading anything off it
pub fn RunCollisionEndScripts(engine_context: *EngineContext, event: CollisionEndEvent) !void {
    //apart, or one side gone, so there is no direction between them
    const no_normal = std.mem.zeroes(@FieldType(CollisionInfo, "mNormal"));
    if (event.mOrigin.IsActive()) {
        try RunCollisionScripts(OnCollisionEndScript, engine_context, event.mOrigin, event.mTarget, &CollisionInfo{
            .mNormal = no_normal,
            .mIsTrigger = event.mIsTrigger,
            .mSelfCollider = event.mOriginCollider,
            .mOtherCollider = event.mTargetCollider,
        });
    }
    if (event.mTarget.IsActive()) {
        try RunCollisionScripts(OnCollisionEndScript, engine_context, event.mTarget, event.mOrigin, &CollisionInfo{
            .mNormal = no_normal,
            .mIsTrigger = event.mIsTrigger,
            .mSelfCollider = event.mTargetCollider,
            .mOtherCollider = event.mOriginCollider,
        });
    }
}

/// Runs the OnPreSolve scripts of both main objects in a solid contact the solver is about to act on, and writes
/// whether it should back into the event. From the middle of the physics step, see PreSolveEvent. The contact stays
/// enabled only if both sides leave it so, and once one side has switched it off the other's scripts are not asked
pub fn RunPreSolveScripts(engine_context: *EngineContext, event: PreSolveEvent) !void {
    var origin_info: PreSolveInfo = .{
        .mNormal = event.mNormal,
        .mSeparation = event.mSeparation,
        .mSelfCollider = event.mOriginCollider,
        .mOtherCollider = event.mTargetCollider,
    };
    try RunCollisionScripts(OnPreSolveScript, engine_context, event.mOrigin, event.mTarget, &origin_info);
    if (!origin_info.mEnabled) {
        event.mEnabled.* = false;
        return;
    }

    var target_info: PreSolveInfo = .{
        .mNormal = event.mNormal.Neg(),
        .mSeparation = event.mSeparation,
        .mSelfCollider = event.mTargetCollider,
        .mOtherCollider = event.mOriginCollider,
    };
    try RunCollisionScripts(OnPreSolveScript, engine_context, event.mTarget, event.mOrigin, &target_info);
    event.mEnabled.* = target_info.mEnabled;
}

/// A physics step is about to start on e.mWorld: the world's OnPhysicsUpdate scripts run now, at the step's own rate.
/// A scene's first, the rules, then its entities'
pub fn RunPhysicsUpdateScripts(engine_context: *EngineContext, e: PhysicsEventData.StepBeginEvent) !void {
    _ = try RunScriptInWorld(Scene, SComponents.OnPhysicsUpdateScript, e.mWorld, engine_context, .{e.mDT});
    _ = try RunScriptInWorld(Entity, EComponents.OnPhysicsUpdateScript, e.mWorld, engine_context, .{e.mDT});
}

/// What a physics step had to report, see PhysicsEventData: the callback a program processes a world's PostPhysics
/// category with. No else, so a new physics event has to be given an arm here
pub fn OnPhysicsEvent(_: *anyopaque, engine_context: *EngineContext, event: *const PhysicsEvent) anyerror!EventResult {
    switch (event.*) {
        .Default => {},
        //dispatched synchronously, never queued, see the programs' OnEvent
        .StepBegin, .PreSolve => {},
        .CollisionBegin => |e| try RunCollisionBeginScripts(engine_context, e),
        .CollisionEnd => |e| try RunCollisionEndScripts(engine_context, e),
    }
    return .Continue;
}

/// Runs owner's own collision scripts of one type. Nothing is checked for them first: every one is
/// handed the collision, and it is the script that looks at what it hit. Unlike RunScript this starts
/// from the one object and walks its script children, since a collision is about two entities and
/// not every entity in the world. A script that returns false stops the ones after it.
/// info is a pointer to the script type's info (CollisionInfo, PreSolveInfo), so a script can write back into it
fn RunCollisionScripts(comptime script_type: type, engine_context: *EngineContext, owner: Entity, other: Entity, info: anytype) !void {
    _ValidateScriptType(Entity, script_type);

    var script_iter = owner.GetIterator(.Script);
    while (script_iter.next()) |script| {
        if (!script.HasComponent(script_type)) continue;

        const script_component = script.GetComponent(ScriptComponent) orelse continue;
        if (RunHook(Entity, script_type, engine_context, script_component, &owner, .{ &other, info }) == .Handled) return;
    }
}

/// Hands the pointer's and the UI's events to the event scripts of the entities they are sent to (OnPointerEventScript,
/// OnUIEventScript), one batch at a time, the way the batch is processed. Only the scripts of the entity an event is
/// sent to run, and they are handed the event without who it is for: they are its scripts, so it is always for them.
/// One thing that happened (a click, a drop, a text input getting the keyboard) is sent as one event to each entity in
/// a chain, the one it happened to first and then each one it is inside, next to each other in the batch. A script
/// that hands back .Handled for one of them keeps it from the rest of that chain. Enter and exit are each entity's
/// own, so nothing stops them
pub const EventScripts = struct {
    /// The last thing a script handled in this batch: the chain's later events for it are skipped
    mHandled: ?Moment = null,

    /// One thing that happened, as the events of its chain all describe it
    pub const Moment = struct {
        Kind: u16,
        Target: Entity,
        /// tells two clicks of different buttons on the same thing apart
        Button: u8 = 0,

        fn Same(a: Moment, b: Moment) bool {
            return a.Kind == b.Kind and a.Button == b.Button and a.Target.mID == b.Target.mID and a.Target.mManager == b.Target.mManager;
        }
    };

    /// Starts a new batch: nothing handled in it yet
    pub fn Reset(self: *EventScripts) void {
        self.mHandled = null;
    }

    pub fn OnPointerEvent(self: *EventScripts, engine_context: *EngineContext, event: EntityPointerEvent) !void {

        const zone = Tracy.ZoneInit("EventScripts::OnPointerEvent", @src());

        defer zone.Deinit();
        try self.Run(OnPointerEventScript, engine_context, event);
    }

    pub fn OnUIEvent(self: *EventScripts, engine_context: *EngineContext, event: EntityUIEvent) !void {

        const zone = Tracy.ZoneInit("EventScripts::OnUIEvent", @src());

        defer zone.Deinit();
        try self.Run(OnUIEventScript, engine_context, event);
    }

    fn Run(self: *EventScripts, comptime script_type: type, engine_context: *EngineContext, event: anytype) !void {
        if (!self.ShouldRun(event)) return;
        const result = try RunOwnScripts(Entity, script_type, engine_context, event.mEntity, .{&event.mEvent});
        self.After(event, result);
    }

    /// Whether `event` still goes to its entity's scripts: it is sent to one that is still there, and no script before
    /// it in its chain has handled what it is about
    pub fn ShouldRun(self: *const EventScripts, event: anytype) bool {
        if (!event.mEntity.IsActive()) return false;
        const moment = MomentOf(event) orelse return true;
        const handled = self.mHandled orelse return true;
        return !moment.Same(handled);
    }

    /// What `event`'s scripts handed back: once one handled it, the rest of its chain is skipped
    pub fn After(self: *EventScripts, event: anytype, result: ScriptResult) void {
        if (result != .Handled) return;
        if (MomentOf(event)) |moment| self.mHandled = moment;
    }

    /// The thing that happened that an event is one of a chain's events for, null for an event that is only its
    /// entity's own (an enter, an exit)
    pub fn MomentOf(event: anytype) ?Moment {
        return switch (event.mEvent) {
            inline else => |e| blk: {
                const E = @TypeOf(e);
                if (!@hasField(E, "mTarget")) {
                    //a drop goes to the one target alone, it has no chain to stop
                    break :blk null;
                }
                break :blk Moment{
                    .Kind = @intFromEnum(std.meta.activeTag(event.mEvent)),
                    .Target = e.mTarget,
                    .Button = if (@hasField(E, "mButton")) @intFromEnum(e.mButton) else 0,
                };
            },
        };
    }
};

/// Runs `owner`'s own scripts of one type, in order, until one hands back .Handled. Unlike RunScript only the one
/// object's, e.g. the start scripts of a scene that has just loaded
pub fn RunOwnScripts(comptime ObjectType: type, comptime script_type: type, engine_context: *EngineContext, owner: ObjectType, args: anytype) !ScriptResult {
    _ValidateScriptType(ObjectType, script_type);

    var script_iter = owner.GetIterator(.Script);
    while (script_iter.next()) |script| {
        if (!script.HasComponent(script_type)) continue;

        const script_component = script.GetComponent(ScriptComponent) orelse continue;
        if (RunHook(ObjectType, script_type, engine_context, script_component, &owner, args) == .Handled) return .Handled;
    }
    return .Continue;
}

/// Hands the game events sent in `world` for `phase` (WorldManager.Emit) to every script in it with a handler for them,
/// in the order they were sent. For each event: the game context's scripts first, then the players', the scenes' and
/// the entities', top of the scene stack first, and a handler handing back .Handled keeps it from the rest. An event sent
/// for the same phase while this runs is handled in this same pass. The phase's queue is empty after
pub fn ProcessGameEvents(engine_context: *EngineContext, world: *WorldManager, comptime phase: GamePhase) !void {
    const zone = Tracy.ZoneInit("ScriptsProcessor::ProcessGameEvents(" ++ @tagName(phase) ++ ")", @src());
    defer zone.Deinit();

    const queue = world.mGameEventManager.GetQueue(phase);
    defer world.mGameEventManager.Clear(phase);

    var index: usize = 0;
    //by index: a handler can send more, which go on the end and can move the queue
    while (index < queue.mEntries.items.len) : (index += 1) {
        const entry = queue.mEntries.items[index];
        //the handlers are handed a copy, aligned for any event, which a handler sending an event can't move
        const copy = try engine_context.FrameAllocator().alignedAlloc(u8, .@"16", @max(entry.mSize, 1));
        @memcpy(copy[0..entry.mSize], queue.BytesOf(index));
        _ = try RunEventHandlers(engine_context, world, entry.mId, copy.ptr);
    }
    zone.Value(index);
}

/// Runs every handler in `world` for the game event with id `id`, whose bytes are at `event`, until one hands back
/// .Handled
fn RunEventHandlers(engine_context: *EngineContext, world: *WorldManager, id: u64, event: *const anyopaque) !ScriptResult {
    inline for (.{ GameContext, Player, Scene, Entity }) |ObjectType| {
        const manager = world.GetManager(ObjectType);
        const script_ids = try manager.GetGroup(engine_context.FrameAllocator(), GroupQuery{ .Component = GameEventScript });
        SortByOwnerStackPos(ObjectType, world, script_ids.items);
        for (script_ids.items) |script_id| {
            const script_component = manager.GetComponent(ScriptComponent, script_id) orelse continue;
            const owner = ObjectType{ .mID = OwnerOf(ObjectType, world, script_id), .mManager = world };
            if (RunHandler(ObjectType, engine_context, script_component, &owner, id, event) == .Handled) return .Handled;
        }
    }
    return .Continue;
}

/// Runs one script child's handler for the game event with id `id`, if it has one and can run (see RunHook)
fn RunHandler(comptime ObjectType: type, engine_context: *EngineContext, script_component: *const ScriptComponent, owner: *const ObjectType, id: u64, event: *const anyopaque) ScriptResult {
    const instance_id = script_component.mInstance orelse return .Continue;
    const script_asset = ScriptValues.AssetOf(script_component) orelse return .Continue;
    if (script_asset.mStopped or script_asset.GetOwner() != ScriptABI.OwnerKind.Of(ObjectType)) return .Continue;
    const handler = script_asset.GetInfo().HandlerFor(id) orelse return .Continue;
    const instance = script_asset.GetInstance(instance_id) orelse return .Continue;

    const script_zone = Tracy.ZoneInit("ScriptsProcessor::EventHandler", @src());
    defer script_zone.Deinit();
    if (Tracy.enable_tracy) script_zone.Name(script_component.mScriptAssetHandle.GetFileMetaData().mRelPath.items);

    return ScriptAsset.RunHandler(ObjectType, handler, engine_context, owner, instance, event);
}

/// Catches the scripts in `worlds` up with the files that changed last frame (AManager.FileChanged): each script whose
/// own file or a project file it imports changed is built again and swapped in, its script children keeping their
/// variables (ScriptAsset.Reload), and each of its script children gets the tags of what it has now (SetUpScript). A
/// script whose own file no longer builds keeps running the last build that did; one that doesn't build after a file it
/// imports changed stops until it does. One that never built is loaded now if it does. Has to come before
/// AManager.OnUpdate, which clears what changed. On a frame where no file changed it does nothing
pub fn SyncScripts(engine_context: *EngineContext, worlds: []const *WorldManager) !void {
    const zone = Tracy.ZoneInit("ScriptsProcessor::SyncScripts", @src());
    defer zone.Deinit();

    const asset_manager = &engine_context.mAssetManager;
    if (!asset_manager.AnyFileChanged()) return;

    const frame_allocator = engine_context.FrameAllocator();
    //each changed script is built once, however many script children run it
    var reloaded: std.AutoHashMapUnmanaged(AssetHandle.Type, void) = .empty;
    for (worlds) |world_manager| {
        inline for (.{ Entity, Scene, Player, GameContext }) |ObjectType| {
            const manager = world_manager.GetManager(ObjectType);
            const script_ids = try manager.GetGroup(frame_allocator, GroupQuery{ .Component = ScriptComponent });
            for (script_ids.items) |script_id| {
                const script_handle = manager.GetComponent(ScriptComponent, script_id).?.mScriptAssetHandle;
                if (script_handle.mID == AssetHandle.NullObject) continue;
                const loaded = asset_manager.GetLoadedAsset(ScriptAsset, script_handle.mID);
                const own_changed = asset_manager.FileChanged(script_handle.mID);
                const import_changed = if (loaded) |script_asset| script_asset.DependencyChanged(engine_context) else false;
                if (!own_changed and !import_changed) continue;
                if (!reloaded.contains(script_handle.mID)) {
                    try reloaded.put(frame_allocator, script_handle.mID, {});
                    if (loaded) |script_asset| {
                        const file_data = script_handle.GetFileMetaData();
                        const abs_path = try asset_manager.GetAbsPath(frame_allocator, file_data.mRelPath.items, file_data.mPathType);
                        _ = try script_asset.Reload(engine_context, abs_path, file_data.mRelPath.items, import_changed);
                    }
                }
                try SetUpScript(ObjectType, .{ .mID = script_id, .mManager = world_manager }, engine_context);
            }
        }
    }
}

/// Gives a script child what it needs to run its script: its variables (an instance in the script's DLL, kept from
/// then on), a tag for each of the script's hooks, and GameEventScript if it handles game events. A script with nothing
/// it can run here gets UntypedScriptTag
/// instead: one that doesn't load (does not compile, say), or one for another kind of object. Done when the script is
/// added (Core.AddScript, which may build the script), and again when its file changes (SyncScripts)
pub fn SetUpScript(comptime ObjectType: type, script: ObjectType, engine_context: *EngineContext) !void {
    const script_handle = script.GetComponent(ScriptComponent).?.mScriptAssetHandle;
    const script_asset: ?*ScriptAsset = script_handle.GetAsset(engine_context, ScriptAsset) catch |err| switch (err) {
        //it failed to load, the reason is already logged
        error.NoDefaultAsset => null,
        else => return err,
    };

    if (script_asset) |asset| {
        if (script.GetComponent(ScriptComponent).?.mInstance == null) {
            const id = try asset.NewInstance(engine_context, null);
            script.GetComponent(ScriptComponent).?.mInstance = id;
        }
    }

    //tags carry no value to move, so they are safe to take off now
    if (script.HasComponent(UntypedScriptTag)) try script.RemoveComponentSync(engine_context, UntypedScriptTag);
    if (script.HasComponent(GameEventScript)) try script.RemoveComponentSync(engine_context, GameEventScript);
    inline for (comptime ScriptsListFor(ObjectType)) |tag_type| {
        if (script.HasComponent(tag_type)) try script.RemoveComponentSync(engine_context, tag_type);
    }

    if (script_asset) |asset| {
        if (asset.GetOwner() == ScriptABI.OwnerKind.Of(ObjectType)) {
            inline for (comptime ScriptsListFor(ObjectType)) |tag_type| {
                if (asset.HasHook(tag_type.Hook)) _ = try script.AddComponent(engine_context, tag_type{});
            }
            if (asset.GetInfo().mHandlerCount != 0) _ = try script.AddComponent(engine_context, GameEventScript{});
            return;
        }
        std.log.warn("{s} is a script for a {s}, which doesn't go on a {s}, so it will not run", .{ script_handle.GetFileMetaData().mRelPath.items, @tagName(asset.GetOwner()), Tracy.ShortTypeName(ObjectType) });
    }
    _ = try script.AddComponent(engine_context, UntypedScriptTag{});
}

/// Scripts run top layer first, matching the order scenes are drawn in. The sort is
/// stable, so scripts sharing a layer keep the order the ECS handed them back, and for
/// object types with no place in the scene stack it leaves the list alone.
fn SortByOwnerStackPos(comptime ObjectType: type, world_manager: *WorldManager, script_ids: []ObjectType.Type) void {
    if (ObjectType != Entity and ObjectType != Scene) return;

    const Sorter = struct {
        fn StackPosOf(wm: *WorldManager, script_id: ObjectType.Type) usize {
            return OwnerStackPos(ObjectType, wm, OwnerOf(ObjectType, wm, script_id));
        }
        fn lessThan(wm: *WorldManager, a: ObjectType.Type, b: ObjectType.Type) bool {
            return StackPosOf(wm, b) < StackPosOf(wm, a);
        }
    };

    std.sort.insertion(ObjectType.Type, script_ids, world_manager, Sorter.lessThan);
}

/// The object a script belongs to. Scripts are created through CreateChild(.Script), so the
/// ECS ChildComponent is what records the owner.
fn OwnerOf(comptime ObjectType: type, world_manager: *WorldManager, script_id: ObjectType.Type) ObjectType.Type {
    const child_component = world_manager.GetManager(ObjectType).GetComponent(ChildComponent(ObjectType.Type), script_id) orelse return ObjectType.NullObject;
    return child_component.mParent;
}

/// Where the script's owner sits in the scene stack. A scene answers for itself, an
/// entity answers with the scene it lives in, and anything that never went through
/// CreateScene reports 0 so it sorts last rather than crashing.
fn OwnerStackPos(comptime ObjectType: type, world_manager: *WorldManager, owner_id: ObjectType.Type) usize {
    if (ObjectType == Scene) {
        const stack_pos = world_manager.mSManager.GetComponent(StackPosComponent, owner_id) orelse return 0;
        return stack_pos.mPosition;
    } else if (ObjectType == Entity) {
        const scene_component = world_manager.mEManager.GetComponent(EntitySceneComponent, owner_id) orelse return 0;
        const stack_pos = world_manager.mSManager.GetComponent(StackPosComponent, scene_component.mScene.mID) orelse return 0;
        return stack_pos.mPosition;
    } else {
        return 0;
    }
}

/// The script tags an object of this type is allowed to carry.
fn ScriptsListFor(comptime ObjectType: type) []const type {
    if (ObjectType == Entity) {
        return &EComponents.ScriptsList;
    } else if (ObjectType == GameContext) {
        return &GCComponents.ScriptsList;
    } else if (ObjectType == Player) {
        return &PComponents.ScriptsList;
    } else if (ObjectType == Scene) {
        return &SComponents.ScriptsList;
    } else {
        @compileError(std.fmt.comptimePrint("{s} is not a scriptable object type", .{@typeName(ObjectType)}));
    }
}

fn _ValidateScriptType(comptime ObjectType: type, comptime script_type: type) void {
    comptime var is_valid: bool = false;
    const scripts_list = comptime ScriptsListFor(ObjectType);
    inline for (scripts_list) |s_type| {
        if (script_type == s_type) {
            is_valid = true;
        }
    }
    if (is_valid == false) {
        @compileError(std.fmt.comptimePrint("{s} is not a script type for {s}\n", .{ @typeName(script_type), @typeName(ObjectType) }));
    }
}
