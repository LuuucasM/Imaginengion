//! What each hook of a script lists it touches, its Reads and Writes: locked while that hook runs as a system from its
//! owner's ECS (ScriptExport.HookSystem), with the owner's ScriptComponent, and the only components a Debug build lets
//! it get pointers into. No DLL is built: the scripts are
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
const RigidBodyComponent = EntityComponents.RigidBodyComponent;
const EManager = @import("../../ECSManagers/EManager.zig");
const OnUpdateScript = EntityComponents.OnUpdateScript;
const ScriptABI = @import("../../Scripts/ScriptABI.zig");
const ScriptExport = @import("../../Scripts/ScriptExport.zig");
const ScriptsProcessor = @import("../../Scripts/ScriptsProcessor.zig");
const Systems = @import("../../ECS/Systems.zig");
const SManager = @import("../../ECSManagers/SManager.zig");
const ScriptComponent = @import("../../ECSComponents/Shared/ScriptComponent.zig");
const ScenePhysicsComponent = @import("../../ECSComponents/SComponents.zig").PhysicsComponent;

/// What the scripts below saw while their hooks ran
const Seen = struct {
    mTransformLocked: bool = false,
    mAllowsTransform: bool = false,
    mAllowsRigidBody: bool = true,
    mSpawnStaged: bool = false,
    mSpawn: Entity = .uninit,
    mOwnerAliveAfterDelete: bool = false,
};
var gSeen: Seen = .{};

/// Writes transforms, and makes a new entity with one
const Spawner = struct {
    pub const OnUpdate = struct {
        //the scene it makes the entity in, from its owner's
        pub const Reads = &.{EntityComponents.EntitySceneComponent};
        pub const Writes = &.{TransformComponent};

        pub fn Run(_: *Spawner, engine_context: *EngineContext, owner: Entity) !ScriptABI.ScriptResult {
            const entity_ecs = &owner.mManager.mEManager.mECSManager;
            gSeen.mTransformLocked = entity_ecs.mLockCounts[EManager.ECSManagerT.ComponentInd(TransformComponent)] > 0;
            gSeen.mAllowsTransform = entity_ecs.AllowsAccess(TransformComponent);
            gSeen.mAllowsRigidBody = entity_ecs.AllowsAccess(RigidBodyComponent);

            const transforms_before = entity_ecs.NumWithComponent(TransformComponent);
            const scene = owner.GetComponent(EntityComponents.EntitySceneComponent).?.mScene;
            gSeen.mSpawn = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
            //it reads as having its transform, but the array didn't take it while the script was running
            gSeen.mSpawnStaged = gSeen.mSpawn.HasComponent(TransformComponent) and
                entity_ecs.NumWithComponent(TransformComponent) == transforms_before;
            return .Continue;
        }
    };
};
const SpawnerExports = ScriptExport.Exports(Spawner, "Spawner", &.{});

/// Deletes the object it is on
const SelfDeleter = struct {
    pub const OnUpdate = struct {
        pub const Reads = &.{};
        pub const Writes = &.{};

        pub fn Run(_: *SelfDeleter, engine_context: *EngineContext, owner: Entity) !ScriptABI.ScriptResult {
            try owner.Delete(engine_context);
            gSeen.mOwnerAliveAfterDelete = owner.IsActive();
            return .Continue;
        }
    };
};
const SelfDeleterExports = ScriptExport.Exports(SelfDeleter, "SelfDeleter", &.{});

/// What TwoHooks saw in each of its hooks
const HookSeen = struct {
    mTransformLocked: bool = false,
    mRigidBodyLocked: bool = true,
    mScriptLocks: u16 = 0,
    mScenePhysicsLocked: bool = true,
};
var gUpdateSeen: HookSeen = .{};
var gPhysicsSeen: HookSeen = .{};

fn SeeLocks(seen: *HookSeen, owner: Entity) void {
    const entity_ecs = &owner.mManager.mEManager.mECSManager;
    const scene_ecs = &owner.mManager.mSManager.mECSManager;
    seen.mTransformLocked = entity_ecs.mLockCounts[EManager.ECSManagerT.ComponentInd(TransformComponent)] > 0;
    seen.mRigidBodyLocked = entity_ecs.mLockCounts[EManager.ECSManagerT.ComponentInd(RigidBodyComponent)] > 0;
    seen.mScriptLocks = entity_ecs.mLockCounts[EManager.ECSManagerT.ComponentInd(ScriptComponent)];
    seen.mScenePhysicsLocked = scene_ecs.mLockCounts[SManager.ECSManagerT.ComponentInd(ScenePhysicsComponent)] > 0;
}

/// Two hooks touching different things: each is locked by its own lists only
const TwoHooks = struct {
    pub const OnUpdate = struct {
        pub const Reads = &.{};
        pub const Writes = &.{TransformComponent};

        pub fn Run(_: *TwoHooks, _: *EngineContext, owner: Entity) ScriptABI.ScriptResult {
            SeeLocks(&gUpdateSeen, owner);
            return .Continue;
        }
    };

    pub const OnPhysicsUpdate = struct {
        //the scene's gravity, from the scene ECS
        pub const Reads = &.{Systems.In(SManager.ECSManagerT, ScenePhysicsComponent)};
        pub const Writes = &.{RigidBodyComponent};

        pub fn Run(_: *TwoHooks, _: *EngineContext, owner: Entity, _: f32) ScriptABI.ScriptResult {
            SeeLocks(&gPhysicsSeen, owner);
            return .Continue;
        }
    };
};
const TwoHooksExports = ScriptExport.Exports(TwoHooks, "TwoHooks", &.{});

const TestWorld = struct {
    mEngineContext: *EngineContext,
    mScene: Scene = .uninit,

    fn Init() !*TestWorld {
        const self = try std.heap.page_allocator.create(TestWorld);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        //UUIDs are drawn from the context's Io, which forwards to this
        engine_context._Internal.ThreadedIO = std.Io.Threaded.init(engine_context._Internal.EngineGPA.allocator(), .{
            .concurrent_limit = .nothing,
            .async_limit = .nothing,
        });
        try engine_context.mAssetManager.Init(engine_context);
        try engine_context.mGameWorld.Init(engine_context);
        self.mScene = try engine_context.mGameWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        const engine_allocator = engine_context.EngineAllocator();
        //the scripts give their variables back to the assets first
        engine_context.mGameWorld.Deinit(engine_context);
        engine_context.mSerializer.Deinit(engine_allocator);

        const asset_manager = &engine_context.mAssetManager;
        asset_manager.mECSManager.Deinit(engine_context);
        asset_manager.mUUIDToWorldID.deinit(engine_allocator);
        asset_manager.mEventManager.Deinit(engine_allocator);
        asset_manager.mCWDPath.deinit(engine_allocator);

        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    /// A loaded script asset running `info`, as if its DLL had handed it over. The handle is the caller's reference
    fn ScriptAssetFor(self: *TestWorld, info: *const ScriptABI.ScriptInfo) !AssetHandle {
        const engine_context = self.mEngineContext;
        const asset_manager = &engine_context.mAssetManager;
        const engine_allocator = engine_context.EngineAllocator();
        const asset_id = try asset_manager.mECSManager.CreateEntity(engine_allocator);
        _ = try asset_manager.mECSManager.AddComponentSync(engine_context, asset_id, Assets.AssetMetaData{ .mRefs = 1 });
        var file_meta_data = Assets.FileMetaData{ .mPathType = .Prj };
        _ = try file_meta_data.mRelPath.print(engine_allocator, "scripts/Test.zig", .{});
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

test "what a script lists is locked while it runs, and it may touch only that" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    gSeen = .{};

    var handle = try world.ScriptAssetFor(&SpawnerExports.info);
    defer handle.ReleaseAsset();
    _ = try world.EntityWithScript(handle);
    const entity_ecs = &world.mEngineContext.mGameWorld.mEManager.mECSManager;

    try world.RunUpdateScripts();

    try std.testing.expect(gSeen.mTransformLocked);
    try std.testing.expect(gSeen.mAllowsTransform);
    try std.testing.expect(!gSeen.mAllowsRigidBody);
    //what it made with a listed component waited for it to finish, and is there now
    try std.testing.expect(gSeen.mSpawnStaged);
    try std.testing.expect(gSeen.mSpawn.HasComponent(TransformComponent));
    try std.testing.expectEqual(@as(u32, 0), entity_ecs.mLockTotal);
    //and nothing is checked once the scripts are done
    try std.testing.expect(entity_ecs.AllowsAccess(RigidBodyComponent));
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

test "each hook is locked by its own lists, its owner's script component too" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    gUpdateSeen = .{};
    gPhysicsSeen = .{};

    var handle = try world.ScriptAssetFor(&TwoHooksExports.info);
    defer handle.ReleaseAsset();
    _ = try world.EntityWithScript(handle);
    const game_world = &world.mEngineContext.mGameWorld;

    try world.RunUpdateScripts();
    try ScriptsProcessor.RunPhysicsUpdateScripts(world.mEngineContext, .{ .mWorld = game_world, .mDT = 1.0 / 60.0 });

    //OnUpdate: its transform, not the physics hook's
    try std.testing.expect(gUpdateSeen.mTransformLocked);
    try std.testing.expect(!gUpdateSeen.mRigidBodyLocked);
    try std.testing.expect(!gUpdateSeen.mScenePhysicsLocked);
    //OnPhysicsUpdate: its rigid body, and through In the scene's physics in the scene ECS
    try std.testing.expect(gPhysicsSeen.mRigidBodyLocked);
    try std.testing.expect(gPhysicsSeen.mScenePhysicsLocked);
    try std.testing.expect(!gPhysicsSeen.mTransformLocked);
    //the hook locks the script component on top of the script runner's own lock
    try std.testing.expectEqual(@as(u16, 2), gUpdateSeen.mScriptLocks);
    try std.testing.expectEqual(@as(u16, 2), gPhysicsSeen.mScriptLocks);
    try std.testing.expectEqual(@as(u32, 0), game_world.mEManager.mECSManager.mLockTotal);
    try std.testing.expectEqual(@as(u32, 0), game_world.mSManager.mECSManager.mLockTotal);
}
