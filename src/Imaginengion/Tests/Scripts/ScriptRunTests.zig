//! What a script's hooks can count on: they run inside the run of a script loop (ScriptsProcessor), so what they add,
//! remove or delete waits for the scripts to be done, reading as done straight away. No DLL is built: the scripts are
//! exported in-process (ScriptExport.Exports) and put straight onto an asset, and run the way the engine runs them.
//! Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const AssetHandle = @import("../../ECSObjects/AssetHandle.zig");
const ECSObject = @import("../../ECSObjects/ECSObject.zig");
const Assets = @import("../../ECSComponents/AComponents.zig");
const ScriptAsset = Assets.ScriptAsset;
const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const TransformComponent = EntityComponents.TransformComponent;
const OnUpdateScript = EntityComponents.OnUpdateScript;
const ScriptABI = @import("../../Scripts/ScriptABI.zig");
const ScriptExport = @import("../../Scripts/ScriptExport.zig");
const ScriptsProcessor = @import("../../Scripts/ScriptsProcessor.zig");

/// What the scripts below saw while their hooks ran
const Seen = struct {
    mSpawnStaged: bool = false,
    mSpawnFound: bool = false,
    mSpawn: Entity = .uninit,
    mOwnerAliveAfterDelete: bool = false,
};
var gSeen: Seen = .{};

/// Makes a new entity with a transform, and looks for it
const Spawner = struct {
    pub fn OnUpdate(_: *Spawner, engine_context: *EngineContext, owner: Entity) !ScriptABI.ScriptResult {
        const entity_ecs = &owner.mManager.mEManager.mECSManager;
        const transforms_before = entity_ecs.NumWithComponent(TransformComponent);
        const scene = owner.GetComponent(EntityComponents.EntitySceneComponent).?.mScene;
        gSeen.mSpawn = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
        //it reads as having its transform, but the array didn't take it while the script was running
        gSeen.mSpawnStaged = gSeen.mSpawn.HasComponent(TransformComponent) and
            entity_ecs.mComponentManager.NumWithComponent(TransformComponent) == transforms_before;
        //and a query finds it, the way it does once it lands
        const in_scene = try scene.GetEntityGroup(engine_context.Scratch(), .{ .Component = EntityComponents.EntitySceneComponent });
        gSeen.mSpawnFound = std.mem.indexOfScalar(Entity.Type, in_scene.items, gSeen.mSpawn.mID) != null;
        return .Continue;
    }
};
const SpawnerExports = ScriptExport.Exports(Spawner, "Spawner", &.{});

/// Deletes the object it is on
const SelfDeleter = struct {
    pub fn OnUpdate(_: *SelfDeleter, engine_context: *EngineContext, owner: Entity) !ScriptABI.ScriptResult {
        try owner.Delete(engine_context);
        gSeen.mOwnerAliveAfterDelete = owner.IsActive();
        return .Continue;
    }
};
const SelfDeleterExports = ScriptExport.Exports(SelfDeleter, "SelfDeleter", &.{});

/// What Mover hands back after moving its owner
var gMoverResult: ScriptABI.ScriptResult = .Continue;

/// Moves its owner to x = 7, then hands back gMoverResult. A hook's error becomes .Error before the runner sees it
/// (ScriptExport.Finish), which logs it, so .Error is handed back as it is here to keep the test's log clean
const Mover = struct {
    pub fn OnUpdate(_: *Mover, engine_context: *EngineContext, owner: Entity) !ScriptABI.ScriptResult {
        try owner.SetTranslation(engine_context, .{ .x = 7, .y = 0, .z = 0 });
        return gMoverResult;
    }
};
const MoverExports = ScriptExport.Exports(Mover, "Mover", &.{});

const TestWorld = struct {
    mEngineContext: *EngineContext,
    mScene: Scene = .uninit,

    fn Init() !*TestWorld {
        const self = try std.heap.page_allocator.create(TestWorld);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        //UUIDs are drawn from the context's Io, which forwards to this
        engine_context._Internal.ThreadPool = std.Io.Threaded.init(engine_context._Internal.KeepHeap.allocator(), .{
            .concurrent_limit = .nothing,
            .async_limit = .nothing,
        });
        try engine_context.mAssetManager.Init(engine_context);
        //a UI element added by a script is adopted by it (Manager.OnComponentAdded)
        try engine_context.mUIManager.Init(engine_context);
        try engine_context.mGameWorld.Init(engine_context);
        self.mScene = try engine_context.mGameWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        const keep_allocator = engine_context.Keep();
        //the scripts give their variables back to the assets first
        engine_context.mGameWorld.Deinit(engine_context);
        engine_context.mSerializer.Deinit(keep_allocator);

        const asset_manager = &engine_context.mAssetManager;
        asset_manager.mECSManager.Deinit(engine_context);
        asset_manager.mUUIDToWorldID.deinit(keep_allocator);
        asset_manager.mEventManager.Deinit(keep_allocator);
        asset_manager.mCWDPath.deinit(keep_allocator);
        engine_context.mUIManager.Deinit(engine_context);

        _ = engine_context._Internal.KeepHeap.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    /// A loaded script asset running `info`, as if its DLL had handed it over. The handle is the caller's reference
    fn ScriptAssetFor(self: *TestWorld, info: *const ScriptABI.ScriptInfo) !AssetHandle {
        const engine_context = self.mEngineContext;
        const asset_manager = &engine_context.mAssetManager;
        const keep_allocator = engine_context.Keep();
        const asset_id = try asset_manager.mECSManager.CreateEntity(keep_allocator);
        _ = try asset_manager.mECSManager.AddComponentSync(engine_context, asset_id, Assets.AssetMetaData{ .mRefs = 1 });
        var file_meta_data = Assets.FileMetaData{ .mPathType = .Prj };
        _ = try file_meta_data.mRelPath.print(keep_allocator, "scripts/Test.zig", .{});
        _ = try asset_manager.mECSManager.AddComponentSync(engine_context, asset_id, file_meta_data);
        _ = try asset_manager.mECSManager.AddComponentSync(engine_context, asset_id, ScriptAsset{ ._Info = info });
        return .{ .mID = asset_id, .mManager = asset_manager };
    }

    /// An entity with a script running `handle` (which keeps a reference of its own)
    fn EntityWithScript(self: *TestWorld, handle: AssetHandle) !Entity {
        const engine_context = self.mEngineContext;
        const entity = try self.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
        handle.RetainAsset();
        _ = try ECSObject.Core(Entity).AddScript(entity, engine_context, handle);
        return entity;
    }

    fn RunUpdateScripts(self: *TestWorld) !void {
        _ = try ScriptsProcessor.RunScript(Entity, OnUpdateScript, .Game, self.mEngineContext, .{});
    }
};

test "what a script makes reads as made and a query finds it, and it lands once the scripts are done" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    gSeen = .{};

    var handle = try world.ScriptAssetFor(&SpawnerExports.info);
    defer handle.ReleaseAsset();
    _ = try world.EntityWithScript(handle);
    const entity_ecs = &world.mEngineContext.mGameWorld.mEManager.mECSManager;
    const transforms_before = entity_ecs.mComponentManager.NumWithComponent(TransformComponent);

    try world.RunUpdateScripts();

    try std.testing.expect(gSeen.mSpawnStaged);
    try std.testing.expect(gSeen.mSpawnFound);
    try std.testing.expect(gSeen.mSpawn.HasComponent(TransformComponent));
    try std.testing.expectEqual(transforms_before + 1, entity_ecs.mComponentManager.NumWithComponent(TransformComponent));
    try std.testing.expectEqual(@as(u32, 0), world.mEngineContext.mSystems.mRunDepth);
}

test "a script deleting its own object goes once the scripts are done, not while it runs" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    gSeen = .{};

    var handle = try world.ScriptAssetFor(&SelfDeleterExports.info);
    defer handle.ReleaseAsset();
    const entity = try world.EntityWithScript(handle);

    try world.RunUpdateScripts();

    try std.testing.expect(gSeen.mOwnerAliveAfterDelete);
    try std.testing.expect(!entity.IsActive());
}

test "a scene's group holds its entities, not the script children on them" {
    const world = try TestWorld.Init();
    defer world.Deinit();

    var handle = try world.ScriptAssetFor(&SpawnerExports.info);
    defer handle.ReleaseAsset();
    const entity = try world.EntityWithScript(handle);

    //a script child has a transform too, but no scene
    const with_transforms = try world.mScene.GetEntityGroup(world.mEngineContext.Scratch(), .{ .Component = TransformComponent });
    try std.testing.expectEqualSlices(Entity.Type, &.{entity.mID}, with_transforms.items);
}

/// Runs Mover once on a new entity at x = 0, handing back `result`, and gives the x it is at after
fn MoverEndsAt(result: ScriptABI.ScriptResult) !f32 {
    const world = try TestWorld.Init();
    defer world.Deinit();
    gMoverResult = result;
    defer gMoverResult = .Continue;

    var handle = try world.ScriptAssetFor(&MoverExports.info);
    defer handle.ReleaseAsset();
    const entity = try world.EntityWithScript(handle);

    try world.RunUpdateScripts();

    return entity.GetComponent(TransformComponent).?.GetTranslation().x;
}

test "what a hook changes stays when it carries on or handles what it ran for" {
    try std.testing.expectEqual(@as(f32, 7), try MoverEndsAt(.Continue));
    try std.testing.expectEqual(@as(f32, 7), try MoverEndsAt(.Handled));
}

test "what a hook changes is dropped when it fails or hits an error, as if it never ran" {
    try std.testing.expectEqual(@as(f32, 0), try MoverEndsAt(.Failed));
    try std.testing.expectEqual(@as(f32, 0), try MoverEndsAt(.Error));
}

/// What the failing scripts below made, for the tests to look for afterwards
var gFailedSpawn: Entity = .uninit;
var gFailedSpawnUUID: u64 = 0;

/// Makes a new entity in its owner's scene, then fails
const SpawnsThenFails = struct {
    pub fn OnUpdate(_: *SpawnsThenFails, engine_context: *EngineContext, owner: Entity) !ScriptABI.ScriptResult {
        const scene = owner.GetComponent(EntityComponents.EntitySceneComponent).?.mScene;
        gFailedSpawn = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
        gFailedSpawnUUID = gFailedSpawn.GetComponent(EntityComponents.UUIDComponent).?.ID;
        return .Failed;
    }
};
const SpawnsThenFailsExports = ScriptExport.Exports(SpawnsThenFails, "SpawnsThenFails", &.{});

test "an object a failed hook made is gone after, out of the UUID map and its scene" {
    const world = try TestWorld.Init();
    defer world.Deinit();

    var handle = try world.ScriptAssetFor(&SpawnsThenFailsExports.info);
    defer handle.ReleaseAsset();
    const entity = try world.EntityWithScript(handle);

    try world.RunUpdateScripts();

    try std.testing.expect(!gFailedSpawn.IsActive());
    try std.testing.expect(world.mEngineContext.mGameWorld.mEManager.GetWorldID(gFailedSpawnUUID) == null);
    const in_scene = try world.mScene.GetEntityGroup(world.mEngineContext.Scratch(), .{ .Component = EntityComponents.EntitySceneComponent });
    try std.testing.expectEqualSlices(Entity.Type, &.{entity.mID}, in_scene.items);
}

/// Deletes the object it is on, then fails
const DeletesThenFails = struct {
    pub fn OnUpdate(_: *DeletesThenFails, engine_context: *EngineContext, owner: Entity) !ScriptABI.ScriptResult {
        try owner.Delete(engine_context);
        return .Failed;
    }
};
const DeletesThenFailsExports = ScriptExport.Exports(DeletesThenFails, "DeletesThenFails", &.{});

test "an object a failed hook deleted is still there after the scripts are done" {
    const world = try TestWorld.Init();
    defer world.Deinit();

    var handle = try world.ScriptAssetFor(&DeletesThenFailsExports.info);
    defer handle.ReleaseAsset();
    const entity = try world.EntityWithScript(handle);

    try world.RunUpdateScripts();

    try std.testing.expect(entity.IsActive());
}

/// Gives the object it is on a UI element, which makes one in the UI manager, then fails
const AddsUIThenFails = struct {
    pub fn OnUpdate(_: *AddsUIThenFails, engine_context: *EngineContext, owner: Entity) !ScriptABI.ScriptResult {
        _ = try owner.AddComponent(engine_context, EntityComponents.UIElementComponent{});
        return .Failed;
    }
};
const AddsUIThenFailsExports = ScriptExport.Exports(AddsUIThenFails, "AddsUIThenFails", &.{});

test "a component a failed hook added is gone after, and so is what adding it made elsewhere" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const ui_ecs = &world.mEngineContext.mUIManager.mECSManager;

    var handle = try world.ScriptAssetFor(&AddsUIThenFailsExports.info);
    defer handle.ReleaseAsset();
    const entity = try world.EntityWithScript(handle);
    const elements_before = (try ui_ecs.GetAllEntities(world.mEngineContext.Scratch())).items.len;

    try world.RunUpdateScripts();

    try std.testing.expect(!entity.HasComponent(EntityComponents.UIElementComponent));
    try std.testing.expectEqual(elements_before, (try ui_ecs.GetAllEntities(world.mEngineContext.Scratch())).items.len);
}

//----------------what a failed hook changed outside the ECSs----------------

const GameEvents = @import("../../Scripts/GameEvents.zig");
const PreSolveInfo = @import("../../Physics/Collisions.zig").PreSolveInfo;

/// What Counter hands back, and the count it saw after counting
var gCounterResult: ScriptABI.ScriptResult = .Continue;
var gCounted: u32 = 0;

/// Counts in a script variable each time it runs
const Counter = struct {
    mCount: u32 = 0,

    pub fn OnUpdate(self: *Counter, _: *EngineContext, _: Entity) !ScriptABI.ScriptResult {
        self.mCount += 1;
        gCounted = self.mCount;
        return gCounterResult;
    }
};
const CounterExports = ScriptExport.Exports(Counter, "Counter", &.{});

test "a failed hook's script variables are put back as it found them" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    defer gCounterResult = .Continue;

    var handle = try world.ScriptAssetFor(&CounterExports.info);
    defer handle.ReleaseAsset();
    _ = try world.EntityWithScript(handle);

    gCounterResult = .Failed;
    try world.RunUpdateScripts();
    gCounterResult = .Continue;
    try world.RunUpdateScripts();
    try world.RunUpdateScripts();

    //the failed run's count was put back, so the two kept runs counted from 0
    try std.testing.expectEqual(@as(u32, 2), gCounted);
}

/// What SwitchesContactOff hands back after switching the contact off
var gContactResult: ScriptABI.ScriptResult = .Continue;

/// Lets the other one pass through
const SwitchesContactOff = struct {
    pub fn OnPreSolve(_: *SwitchesContactOff, _: *EngineContext, _: Entity, _: Entity, info: *PreSolveInfo) !ScriptABI.ScriptResult {
        info.mEnabled = false;
        return gContactResult;
    }
};
const SwitchesContactOffExports = ScriptExport.Exports(SwitchesContactOff, "SwitchesContactOff", &.{});

/// Hands a contact between a new entity running SwitchesContactOff and another to the pre-solve scripts, with the script
/// handing back `result`, and gives whether the contact is still on after
fn ContactStaysOn(result: ScriptABI.ScriptResult) !bool {
    const world = try TestWorld.Init();
    defer world.Deinit();
    gContactResult = result;
    defer gContactResult = .Continue;

    var handle = try world.ScriptAssetFor(&SwitchesContactOffExports.info);
    defer handle.ReleaseAsset();
    const ball = try world.EntityWithScript(handle);
    _ = try ball.AddComponent(world.mEngineContext, EntityComponents.OnPreSolveScript{});
    const wall = try world.mScene.CreateEntity(world.mEngineContext, Entity.DefaultConfig);

    var enabled = true;
    try ScriptsProcessor.RunPreSolveScripts(world.mEngineContext, .{
        .mOrigin = ball,
        .mTarget = wall,
        .mOriginCollider = ball,
        .mTargetCollider = wall,
        .mNormal = .{ .x = 1, .y = 0, .z = 0 },
        .mSeparation = -0.1,
        .mEnabled = &enabled,
    });
    return enabled;
}

test "what a failed hook was handed to change is put back: a pre-solve script switching a contact off" {
    try std.testing.expect(!try ContactStaysOn(.Continue));
    try std.testing.expect(try ContactStaysOn(.Failed));
}

/// A game event sent by Sender
const Pinged = struct {
    pub const Phase: GameEvents.GamePhase = .AfterUpdate;
    mFrom: u32 = 7,
};

/// What Sender hands back after sending
var gSenderResult: ScriptABI.ScriptResult = .Continue;

/// Sends a game event and a UI event about the object it is on
const Sender = struct {
    pub fn OnUpdate(_: *Sender, engine_context: *EngineContext, owner: Entity) !ScriptABI.ScriptResult {
        try owner.GetWorld().Emit(engine_context, Pinged{});
        try engine_context.mUIManager.Send(engine_context, owner, .{ .FocusGained = .{ .mTarget = owner } });
        return gSenderResult;
    }
};
const SenderExports = ScriptExport.Exports(Sender, "Sender", &.{});

/// How many game events and UI events are waiting after Sender runs once, handing back `result`
fn EventsSentWith(result: ScriptABI.ScriptResult) !struct { usize, usize } {
    const world = try TestWorld.Init();
    defer world.Deinit();
    gSenderResult = result;
    defer gSenderResult = .Continue;
    const engine_context = world.mEngineContext;

    var handle = try world.ScriptAssetFor(&SenderExports.info);
    defer handle.ReleaseAsset();
    _ = try world.EntityWithScript(handle);
    const ui_before = engine_context.mUIManager.mEventManager.mEventsArray.get(.UI).items.len;

    try world.RunUpdateScripts();

    const game_events = engine_context.mGameWorld.mGameEventManager.GetQueue(GameEvents.PhaseOf(Pinged)).mEntries.items.len;
    const ui_events = engine_context.mUIManager.mEventManager.mEventsArray.get(.UI).items.len - ui_before;
    return .{ game_events, ui_events };
}

test "events a kept hook sends arrive, and events a failed hook sends never do" {
    const kept = try EventsSentWith(.Continue);
    try std.testing.expectEqual(@as(usize, 1), kept[0]);
    try std.testing.expectEqual(@as(usize, 1), kept[1]);

    const failed = try EventsSentWith(.Failed);
    try std.testing.expectEqual(@as(usize, 0), failed[0]);
    try std.testing.expectEqual(@as(usize, 0), failed[1]);
}

/// Moves its owner, does something that can't be taken back, then fails
const IrrevocableThenFails = struct {
    pub fn OnUpdate(_: *IrrevocableThenFails, engine_context: *EngineContext, owner: Entity) !ScriptABI.ScriptResult {
        try owner.SetTranslation(engine_context, .{ .x = 7, .y = 0, .z = 0 });
        try engine_context.mTransactions.MarkIrrevocable("the test said so");
        return .Failed;
    }
};
const IrrevocableThenFailsExports = ScriptExport.Exports(IrrevocableThenFails, "IrrevocableThenFails", &.{});

test "a failed hook that did something that can't be taken back is kept whole" {
    const world = try TestWorld.Init();
    defer world.Deinit();

    var handle = try world.ScriptAssetFor(&IrrevocableThenFailsExports.info);
    defer handle.ReleaseAsset();
    const entity = try world.EntityWithScript(handle);

    try world.RunUpdateScripts();

    try std.testing.expectEqual(@as(f32, 7), entity.GetComponent(TransformComponent).?.GetTranslation().x);
}

//----------------the conflict report----------------

/// The entity both ScoreBumpers change
var gScoreboard: Entity = .uninit;

/// Changes the scoreboard's AttribComponent, the way two Pong scripts would both change the game state
const ScoreBumper = struct {
    pub fn OnUpdate(_: *ScoreBumper, _: *EngineContext, _: Entity) !ScriptABI.ScriptResult {
        const attrib = gScoreboard.GetComponentMut(EntityComponents.AttribComponent).?;
        attrib.mData = .default;
        return .Continue;
    }
};
const ScoreBumperExports = ScriptExport.Exports(ScoreBumper, "ScoreBumper", &.{});

test "two scripts in one loop changing the same component are reported as a conflict, under that loop and type" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const conflicts = &engine_context.mTransactions.mConflicts;

    gScoreboard = try world.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try gScoreboard.AddComponent(engine_context, EntityComponents.AttribComponent{});
    var handle = try world.ScriptAssetFor(&ScoreBumperExports.info);
    defer handle.ReleaseAsset();
    _ = try world.EntityWithScript(handle);
    _ = try world.EntityWithScript(handle);

    conflicts.mOn = true;
    try world.RunUpdateScripts();
    conflicts.mOn = false;

    var found = false;
    for (conflicts.mSystems.keys(), conflicts.mSystems.values()) |name, counts| {
        if (std.mem.indexOf(u8, name, "RunScript") == null) continue;
        found = true;
        try std.testing.expectEqual(@as(u64, 2), counts.mHooks);
        try std.testing.expectEqual(@as(u64, 1), counts.mConflicts);
        try std.testing.expect(std.mem.endsWith(u8, counts.mTypes.keys()[0], "AttribComponent"));
    }
    try std.testing.expect(found);
}

//----------------what a hook in a batch mustn't do while speculating----------------

/// The asset LoadsAsset asks for: listed in the asset manager, never loaded
var gUnloaded: AssetHandle = undefined;
/// What LoadsAsset's runs got back, in order
var gLoadRuns: u32 = 0;
var gFirstLoadError: ?anyerror = null;

/// Asks for an asset that isn't loaded yet on its first run. A per-frame hook, so it runs in a batch
const LoadsAsset = struct {
    pub fn OnUpdate(_: *LoadsAsset, engine_context: *EngineContext, _: Entity) !ScriptABI.ScriptResult {
        gLoadRuns += 1;
        //only the first run asks: run again on its own, it would really load, and there is no file
        if (gLoadRuns == 1) {
            _ = gUnloaded.GetAsset(engine_context, Assets.TextAsset) catch |err| {
                gFirstLoadError = err;
                return err;
            };
        }
        return .Continue;
    }
};
const LoadsAssetExports = ScriptExport.Exports(LoadsAsset, "LoadsAsset", &.{});

test "a hook in a batch asking for an asset that isn't loaded is refused, and run again on its own" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    gLoadRuns = 0;
    gFirstLoadError = null;

    const asset_manager = &engine_context.mAssetManager;
    const asset_id = try asset_manager.mECSManager.CreateEntity(engine_context.Keep());
    _ = try asset_manager.mECSManager.AddComponentSync(engine_context, asset_id, Assets.AssetMetaData{ .mRefs = 1 });
    var file_meta_data = Assets.FileMetaData{ .mPathType = .Prj };
    _ = try file_meta_data.mRelPath.print(engine_context.Keep(), "never/loaded.txt", .{});
    _ = try asset_manager.mECSManager.AddComponentSync(engine_context, asset_id, file_meta_data);
    gUnloaded = .{ .mID = asset_id, .mManager = asset_manager };

    var handle = try world.ScriptAssetFor(&LoadsAssetExports.info);
    defer handle.ReleaseAsset();
    _ = try world.EntityWithScript(handle);

    try world.RunUpdateScripts();

    try std.testing.expect(gFirstLoadError.? == error.RunSerially);
    try std.testing.expectEqual(@as(u32, 2), gLoadRuns);
    //and nothing was loaded while it speculated
    try std.testing.expect(!asset_manager.mECSManager.HasComponent(Assets.TextAsset, asset_id));
}
