//! Spawning copies of each template type (entity, scene, player, game context) and what Fill copies onto them.
//! Templates are made in the simulate world, saved to a file and spawned into the editor world through a real
//! asset handle, so the asset manager loads them into the asset world like it would in the editor. No window or
//! renderer needed. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../Core/EngineContext.zig");
const WorldManager = @import("../Core/WorldManager.zig");
const TextSerializer = @import("../Serializer/TextSerializer.zig");
const AssetHandle = @import("AssetHandle.zig");
const Entity = @import("Entity.zig");
const Scene = @import("Scene.zig");
const Player = @import("Player.zig");
const GameContext = @import("GameContext.zig");

const AssetMetaData = @import("../ECSComponents/AComponents.zig").AssetMetaData;
const EntityComponents = @import("../ECSComponents/EComponents.zig");
const UUIDComponent = EntityComponents.UUIDComponent;
const NameComponent = EntityComponents.NameComponent;
const TransformComponent = EntityComponents.TransformComponent;
const QuadComponent = EntityComponents.QuadComponent;
const EntitySceneComponent = EntityComponents.EntitySceneComponent;
const TmplRefComponent = EntityComponents.TmplRefComponent;
const SceneComponents = @import("../ECSComponents/SComponents.zig");
const SceneComponent = SceneComponents.SceneComponent;
const StackPosComponent = SceneComponents.StackPosComponent;
const SpawnPossComponent = SceneComponents.SpawnPossComponent;
const PlayerComponents = @import("../ECSComponents/PComponents.zig");
const MicComponent = PlayerComponents.MicComponent;
const PossessComponent = PlayerComponents.PossessComponent;
const AttribComponent = @import("../ECSComponents/GCComponents.zig").AttribComponent;
const EntityTagComponent = @import("../ECS/Components.zig").EntityTagComponent;

const EEventData = @import("../Events/EManagerData.zig");
const GCEventData = @import("../Events/GCManagerData.zig");
const PEventData = @import("../Events/PManagerData.zig");
const SEventData = @import("../Events/SManagerData.zig");
const ECSEventData = @import("../Events/ECSEventData.zig");

const TEXTURE_PATH = "src/Imaginengion/EngineAssets/textures/DefaultTexture.png";

const TestWorld = struct {
    mEngineContext: *EngineContext,
    mTmpDir: std.testing.TmpDir,

    fn Init() !*TestWorld {
        const self = try std.heap.page_allocator.create(TestWorld);
        self.* = .{
            .mEngineContext = try std.heap.page_allocator.create(EngineContext),
            .mTmpDir = std.testing.tmpDir(.{}),
        };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        const engine_allocator = engine_context.EngineAllocator();
        //UUIDs and file reads/writes go through the context's Io, which forwards to this
        engine_context._Internal.ThreadedIO = std.Io.Threaded.init(engine_context._Internal.EngineGPA.allocator(), .{
            .concurrent_limit = .nothing,
            .async_limit = .nothing,
        });
        //no Setup: its default assets need the GPU
        try engine_context.mAssetManager.Init(engine_context);
        //the same asset world setup as EngineContext.Init
        try engine_context.mAssetWorld.Init(engine_allocator);
        engine_context.mAssetEntityScene = try engine_context.mAssetWorld.NewScene(engine_context, .GameLayer, Scene.BlankConfig);
        //templates are made in here, copies are spawned into the editor world
        try engine_context.mSimulateWorld.Init(engine_allocator);
        try engine_context.mEditorWorld.Init(engine_allocator);
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        const engine_allocator = engine_context.EngineAllocator();
        //everything that holds asset handles goes while the asset manager is still alive, as in EngineContext.DeInit
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mSimulateWorld.Deinit(engine_context);
        engine_context.mAssetWorld.clearAndFree(engine_context, .All);
        //loading a template with a SpawnPoss queues a UUID resolve in here
        engine_context.mSerializer.Deinit(engine_allocator);
        //the asset manager, minus the default assets Init never set up and the working directory handle it does not own
        const asset_manager = &engine_context.mAssetManager;
        asset_manager.mECSManager.Deinit(engine_context);
        asset_manager.mUUIDToWorldID.deinit(engine_allocator);
        asset_manager.mEventManager.Deinit(engine_allocator);
        asset_manager.mPendingDelete.deinit(engine_allocator);
        asset_manager.mCWDPath.deinit(engine_allocator);
        engine_context.mAssetWorld.Deinit(engine_context);

        _ = engine_context._Internal.EngineGPA.deinit();
        self.mTmpDir.cleanup();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    fn TmplWorld(self: *TestWorld) *WorldManager {
        return &self.mEngineContext.mSimulateWorld;
    }

    fn GameWorld(self: *TestWorld) *WorldManager {
        return &self.mEngineContext.mEditorWorld;
    }

    /// Saves `object` as a template file and returns a handle to it, the way a script or the editor gets one
    fn SaveTmpl(self: *TestWorld, object: anytype, file_name: []const u8) !AssetHandle {
        const engine_context = self.mEngineContext;
        const rel_path = try std.fmt.allocPrint(engine_context.FrameAllocator(), ".zig-cache/tmp/{s}/{s}", .{ self.mTmpDir.sub_path, file_name });
        try TextSerializer.SerializeECSObject(engine_context, object, rel_path);
        return try engine_context.mAssetManager.GetAssetHandle(engine_context, .{ .File = .{ .rel_path = rel_path, .path_type = .Eng } });
    }

    fn Refs(self: *TestWorld, handle: AssetHandle) usize {
        return self.mEngineContext.mAssetManager.mECSManager.GetComponent(AssetMetaData, handle.mID).?.mRefs;
    }

    /// EditorProgram.OnUpdate's end of frame for one world
    fn EndFrame(self: *TestWorld, world: *WorldManager) !void {
        const engine_context = self.mEngineContext;
        var callback_list: std.DoublyLinkedList = .{};
        try world.ProcessEvents(SEventData, .EndOfFrame, engine_context, &callback_list);
        try world.ProcessEvents(GCEventData, .EndOfFrame, engine_context, &callback_list);
        try world.ProcessEvents(PEventData, .EndOfFrame, engine_context, &callback_list);
        try world.ProcessEvents(EEventData, .EndOfFrame, engine_context, &callback_list);
        try world.ProcessEvents(ECSEventData, .EndOfFrame, engine_context, &callback_list);
    }
};

fn SetName(engine_context: *EngineContext, object: anytype, name: []const u8) !void {
    const name_list = &object.GetComponent(NameComponent).?.mName;
    name_list.clearRetainingCapacity();
    try name_list.appendSlice(engine_context.EngineAllocator(), name);
}

fn FirstChild(object: anytype) @TypeOf(object) {
    var iter = object.GetIterator(.Child);
    return iter.next().?;
}

fn ExpectName(object: anytype, expected: []const u8) !void {
    try std.testing.expectEqualStrings(expected, object.GetName());
}

test "spawned entities copy the template's tree, keep their own transform and are separate from each other" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const tmpl_scene = try world.TmplWorld().NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const goblin = try tmpl_scene.CreateEntity(engine_context, Entity.DefaultConfig);
    try SetName(engine_context, goblin, "Goblin");
    try goblin.SetTranslation(engine_context, .{ .x = 7.0, .y = 0.0, .z = 0.0 });
    const texture = try engine_context.mAssetManager.GetAssetHandle(engine_context, .{ .File = .{ .rel_path = TEXTURE_PATH, .path_type = .Eng } });
    _ = try goblin.AddComponent(engine_context, QuadComponent{ .mTexture = texture });
    const sword = try goblin.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    try SetName(engine_context, sword, "Sword");
    try sword.SetTranslation(engine_context, .{ .x = 1.0, .y = 2.0, .z = 0.0 });
    const gem = try sword.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    try SetName(engine_context, gem, "Gem");

    const tmpl = try world.SaveTmpl(goblin, "goblin.imen");
    const scene = try world.GameWorld().NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    const a = try scene.Spawn(engine_context, tmpl);
    const tmpl_refs = world.Refs(tmpl);
    const texture_refs = world.Refs(texture);
    const b = try scene.Spawn(engine_context, tmpl);
    //each copy's TmplRefComponent and Quad hold a reference of their own
    try std.testing.expectEqual(tmpl_refs + 1, world.Refs(tmpl));
    try std.testing.expectEqual(texture_refs + 1, world.Refs(texture));

    //the shell: the template's name, no UUID, a transform of its own rather than the template root's
    try ExpectName(a, "Goblin");
    try std.testing.expect(!a.HasComponent(UUIDComponent));
    try std.testing.expectEqual(tmpl.mID, a.GetComponent(TmplRefComponent).?.mTmpl.mID);
    try std.testing.expectEqual(@as(f32, 0.0), a.GetComponent(TransformComponent).?.GetTranslation().x);
    try std.testing.expectEqual(texture.mID, a.GetComponent(QuadComponent).?.mTexture.mID);

    //the tree below it: copied names and relative transforms, no UUIDs, all in the copy's scene
    const a_sword = FirstChild(a);
    try ExpectName(a_sword, "Sword");
    try std.testing.expect(!a_sword.HasComponent(UUIDComponent));
    try std.testing.expectEqual(@as(f32, 2.0), a_sword.GetComponent(TransformComponent).?.GetTranslation().y);
    try std.testing.expectEqual(scene.mID, a_sword.GetComponent(EntitySceneComponent).?.mScene.mID);
    try ExpectName(FirstChild(a_sword), "Gem");

    //two separate copies: changing one leaves the other alone
    const b_sword = FirstChild(b);
    try std.testing.expect(a_sword.mID != b_sword.mID);
    try SetName(engine_context, a_sword, "Axe");
    try ExpectName(b_sword, "Sword");

    //the template in the asset world is untouched: still just its three entities
    try std.testing.expectEqual(@as(usize, 3), engine_context.mAssetWorld.NumEntitiesWith(EntityTagComponent));

    //deleting one copy takes its tree and its references, the other copy and the template stay
    try a.Delete(engine_context);
    try world.EndFrame(world.GameWorld());
    try std.testing.expect(!a.IsActive());
    try std.testing.expect(!a_sword.IsActive());
    try std.testing.expect(b.IsActive());
    try std.testing.expect(b_sword.IsActive());
    try std.testing.expectEqual(tmpl_refs, world.Refs(tmpl));
    try std.testing.expectEqual(texture_refs, world.Refs(texture));
}

test "filling an object that already has components keeps them: its own name and UUID stay" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const tmpl_scene = try world.TmplWorld().NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const goblin = try tmpl_scene.CreateEntity(engine_context, Entity.DefaultConfig);
    try SetName(engine_context, goblin, "Goblin");
    _ = try goblin.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    const tmpl = try world.SaveTmpl(goblin, "goblin.imen");

    //what a copy placed in the editor looks like: a shell with its own UUID and name
    const scene = try world.GameWorld().NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const placed = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    try SetName(engine_context, placed, "Left Goblin");
    const placed_uuid = placed.GetUUID();
    try placed.SetTmpl(engine_context, tmpl);

    try ExpectName(placed, "Left Goblin");
    try std.testing.expectEqual(placed_uuid, placed.GetUUID());
    try std.testing.expect(!FirstChild(placed).HasComponent(UUIDComponent));
}

test "filling an object with no template is an error" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const scene = try world.GameWorld().NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const entity = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    try std.testing.expectError(error.NoTmplRef, entity.Fill(engine_context));
}

test "spawned scenes copy their entities, take a stack slot and point their spawn at their own copy" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const game_scenes = &world.GameWorld().mSManager;

    const hud = try world.TmplWorld().NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    try SetName(engine_context, hud, "HUD");
    const button = try hud.CreateEntity(engine_context, Entity.DefaultConfig);
    try SetName(engine_context, button, "Button");
    const label = try button.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    try SetName(engine_context, label, "Label");
    const start = try hud.CreateEntity(engine_context, Entity.DefaultConfig);
    try SetName(engine_context, start, "PlayerStart");
    _ = try hud.AddComponent(engine_context, SpawnPossComponent{ .mEntityRef = start });
    const tmpl = try world.SaveTmpl(hud, "hud.imsc");

    const level = try world.GameWorld().NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const a = try world.GameWorld().Spawn(Scene, engine_context, tmpl);
    const b = try world.GameWorld().Spawn(Scene, engine_context, tmpl);

    try ExpectName(a, "HUD");
    try std.testing.expect(!a.HasComponent(UUIDComponent));
    try std.testing.expectEqual(.OverlayLayer, a.GetComponent(SceneComponent).?.mLayerType);

    //slotted above the level, in the order they were spawned
    try std.testing.expectEqual(@as(usize, 3), game_scenes.mNumofLayers);
    try std.testing.expectEqual(@as(usize, 0), level.GetComponent(StackPosComponent).?.mPosition);
    try std.testing.expectEqual(@as(usize, 1), a.GetComponent(StackPosComponent).?.mPosition);
    try std.testing.expectEqual(@as(usize, 2), b.GetComponent(StackPosComponent).?.mPosition);

    //button, label and the spawn point, all in the copy and without UUIDs
    const a_entities = try a.GetEntityGroup(engine_context.FrameAllocator(), .{ .Component = EntitySceneComponent });
    try std.testing.expectEqual(@as(usize, 3), a_entities.items.len);
    for (a_entities.items) |entity_id| {
        try std.testing.expect(!a.GetEntity(entity_id).HasComponent(UUIDComponent));
    }

    //each copy spawns into its own copy of the spawn point, not the template's in the asset world
    const a_start = a.GetComponent(SpawnPossComponent).?.mEntityRef;
    const b_start = b.GetComponent(SpawnPossComponent).?.mEntityRef;
    try std.testing.expect(a_start.IsActive());
    try std.testing.expect(a_start.mManager == world.GameWorld());
    try ExpectName(a_start, "PlayerStart");
    try std.testing.expectEqual(a.mID, a_start.GetComponent(EntitySceneComponent).?.mScene.mID);
    try std.testing.expectEqual(b.mID, b_start.GetComponent(EntitySceneComponent).?.mScene.mID);

    //deleting a copy takes its entities along and closes the gap in the stack
    try a.Delete(engine_context);
    try world.EndFrame(world.GameWorld());
    try std.testing.expect(!a_start.IsActive());
    try std.testing.expect(b_start.IsActive());
    try std.testing.expectEqual(@as(usize, 1), b.GetComponent(StackPosComponent).?.mPosition);
}

test "spawned players copy the template's components and children" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const player = try world.TmplWorld().CreatePlayer(engine_context, .{
        .bAddNameComponent = true,
        .bAddUUIDComponent = true,
        .bAddPossessComponent = true,
        .bAddMicComponent = false,
        .bAddRenderComponent = false,
    });
    try SetName(engine_context, player, "Player One");
    _ = try player.AddComponent(engine_context, MicComponent{});
    const child = try player.CreateChild(engine_context, .Entity, Player.DefaultConfig);
    try SetName(engine_context, child, "Controller");
    const tmpl = try world.SaveTmpl(player, "player_one.impl");

    const a = try world.GameWorld().Spawn(Player, engine_context, tmpl);
    const b = try world.GameWorld().Spawn(Player, engine_context, tmpl);

    try ExpectName(a, "Player One");
    try std.testing.expect(!a.HasComponent(UUIDComponent));
    try std.testing.expect(a.HasComponent(PossessComponent));
    try std.testing.expect(a.HasComponent(MicComponent));
    try ExpectName(FirstChild(a), "Controller");
    try std.testing.expect(!FirstChild(a).HasComponent(UUIDComponent));
    try std.testing.expect(FirstChild(a).mID != FirstChild(b).mID);
}

test "spawned game contexts copy the template's components and children" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const game_context = try world.TmplWorld().CreateGameContext(engine_context, GameContext.DefaultConfig);
    try SetName(engine_context, game_context, "Deathmatch");
    _ = try game_context.AddComponent(engine_context, AttribComponent{ .mData = .{ .float32 = 2.5 } });
    const round = try game_context.CreateChild(engine_context, .Entity, GameContext.DefaultConfig);
    _ = try round.AddComponent(engine_context, AttribComponent{ .mData = .{ .uint32 = 10 } });
    const tmpl = try world.SaveTmpl(game_context, "deathmatch.imgc");

    const a = try world.GameWorld().Spawn(GameContext, engine_context, tmpl);

    try ExpectName(a, "Deathmatch");
    try std.testing.expect(!a.HasComponent(UUIDComponent));
    try std.testing.expectEqual(@as(f32, 2.5), a.GetComponent(AttribComponent).?.mData.float32);
    try std.testing.expectEqual(@as(u32, 10), FirstChild(a).GetComponent(AttribComponent).?.mData.uint32);
    try std.testing.expect(!FirstChild(a).HasComponent(UUIDComponent));
}
