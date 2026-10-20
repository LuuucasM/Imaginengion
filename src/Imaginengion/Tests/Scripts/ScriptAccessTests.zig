//! What a script lists it touches, its Reads and Writes (ScriptExport.AccessOf): locked on its owner's world while each
//! of its hooks runs, and the only components a Debug build lets it get pointers into. No DLL is built: the scripts are
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
    //the scene it makes the entity in, from its owner's
    pub const Reads = &.{EntityComponents.EntitySceneComponent};
    pub const Writes = &.{TransformComponent};

    pub fn OnUpdate(_: *@This(), engine_context: *EngineContext, owner: Entity) !ScriptABI.ScriptResult {
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
const SpawnerExports = ScriptExport.Exports(Spawner, "Spawner", &.{});

/// Deletes the object it is on
const SelfDeleter = struct {
    pub const Reads = &.{};
    pub const Writes = &.{};

    pub fn OnUpdate(_: *@This(), engine_context: *EngineContext, owner: Entity) !ScriptABI.ScriptResult {
        try owner.Delete(engine_context);
        gSeen.mOwnerAliveAfterDelete = owner.IsActive();
        return .Continue;
    }
};
const SelfDeleterExports = ScriptExport.Exports(SelfDeleter, "SelfDeleter", &.{});

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
        try engine_context.mGameWorld.Init(engine_context.EngineAllocator());
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
