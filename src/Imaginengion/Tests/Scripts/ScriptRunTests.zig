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
        const in_scene = try scene.GetEntityGroup(engine_context.FrameAllocator(), .{ .Component = EntityComponents.EntitySceneComponent });
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
