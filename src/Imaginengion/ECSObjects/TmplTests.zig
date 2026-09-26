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

const EntityAsset = @import("../ECSComponents/AComponents.zig").EntityAsset;
const TmplEditPanel = @import("../Imgui/TmplEditPanel.zig");

const TEXTURE_PATH ="src/Imaginengion/EngineAssets/textures/DefaultTexture.png";

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
        //and the template editing world's
        try engine_context.mTmplEditWorld.Init(engine_allocator);
        engine_context.mTmplEditScene = try engine_context.mTmplEditWorld.NewScene(engine_context, .GameLayer, Scene.BlankConfig);
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
        engine_context.mTmplEditWorld.Deinit(engine_context);
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
        const rel_path = try self.TmpPath(file_name);
        try TextSerializer.SerializeECSObject(engine_context, object, rel_path);
        return try engine_context.mAssetManager.GetAssetHandle(engine_context, .{ .File = .{ .rel_path = rel_path, .path_type = .Eng } });
    }

    /// A path in this test's temporary folder, relative to the working directory like an engine asset path
    fn TmpPath(self: *TestWorld, file_name: []const u8) ![]const u8 {
        return std.fmt.allocPrint(self.mEngineContext.FrameAllocator(), ".zig-cache/tmp/{s}/{s}", .{ self.mTmpDir.sub_path, file_name });
    }

    /// The top level keys of a saved file, i.e. which components (and Children/Scripts/Entities) it has
    fn FileKeys(self: *TestWorld, rel_path: []const u8) !std.json.Parsed(std.json.Value) {
        const engine_context = self.mEngineContext;
        const contents = try std.Io.Dir.cwd().readFileAlloc(engine_context.Io(), rel_path, engine_context.FrameAllocator(), .unlimited);
        return try std.json.parseFromSlice(std.json.Value, engine_context.FrameAllocator(), contents, .{});
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

//===================================== Make Template =====================================

/// What every object is left as by MakeTmpl once the frame ends: its own UUID and name, linked to the template,
/// with nothing under it
fn ExpectShell(object: anytype, uuid: u64, name: []const u8) !void {
    try std.testing.expect(object.IsActive());
    try std.testing.expectEqual(uuid, object.GetUUID());
    try ExpectName(object, name);
    try std.testing.expect(object.GetComponent(TmplRefComponent).?.mTmpl.IsIDValid());
    var child_iter = object.GetIterator(.Child);
    try std.testing.expect(child_iter.next() == null);
}

test "making an entity a template writes its whole tree and leaves a shell that keeps its place" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const scene = try world.GameWorld().NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const goblin = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    try SetName(engine_context, goblin, "Goblin");
    try goblin.SetTranslation(engine_context, .{ .x = 7.0, .y = 0.0, .z = 0.0 });
    const texture = try engine_context.mAssetManager.GetAssetHandle(engine_context, .{ .File = .{ .rel_path = TEXTURE_PATH, .path_type = .Eng } });
    _ = try goblin.AddComponent(engine_context, QuadComponent{ .mTexture = texture });
    const sword = try goblin.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    try SetName(engine_context, sword, "Sword");
    const gem = try sword.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    const goblin_uuid = goblin.GetUUID();

    try goblin.MakeTmpl(engine_context, try world.TmpPath("Goblin.imen"), .Eng);
    try world.EndFrame(world.GameWorld());

    //the shell: same UUID, name and place, no quad, nothing under it
    try ExpectShell(goblin, goblin_uuid, "Goblin");
    try std.testing.expectEqual(@as(f32, 7.0), goblin.GetComponent(TransformComponent).?.GetTranslation().x);
    try std.testing.expect(!goblin.HasComponent(QuadComponent));
    try std.testing.expect(!sword.IsActive());
    try std.testing.expect(!gem.IsActive());

    //the template: the whole tree, its own UUID and sitting at the origin
    const tmpl = goblin.GetComponent(TmplRefComponent).?.mTmpl;
    const tmpl_root = (try tmpl.GetAsset(engine_context, EntityAsset)).mObject;
    try std.testing.expect(tmpl_root.GetUUID() != goblin_uuid);
    try std.testing.expectEqual(@as(f32, 0.0), tmpl_root.GetComponent(TransformComponent).?.GetTranslation().x);
    try std.testing.expectEqual(texture.mID, tmpl_root.GetComponent(QuadComponent).?.mTexture.mID);
    try ExpectName(FirstChild(tmpl_root), "Sword");

    //and spawning from it gives the whole tree back
    const copy = try scene.Spawn(engine_context, tmpl);
    try std.testing.expect(copy.HasComponent(QuadComponent));
    try ExpectName(FirstChild(copy), "Sword");
    try std.testing.expect(FirstChild(FirstChild(copy)).IsActive());
}

test "an entity shell saves and loads as just its shell, unfilled" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const scene = try world.GameWorld().NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const goblin = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    try SetName(engine_context, goblin, "Goblin");
    _ = try goblin.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    try goblin.MakeTmpl(engine_context, try world.TmpPath("Goblin.imen"), .Eng);
    try world.EndFrame(world.GameWorld());

    //saved with the level: the scene's one entity is only the shell
    const level_path = try world.TmpPath("level.imsc");
    try TextSerializer.SerializeECSObject(engine_context, scene, level_path);
    const level_json = try world.FileKeys(level_path);
    const shell_json = level_json.value.object.get("Entities").?.array.items[0].object;
    try std.testing.expectEqual(@as(usize, 4), shell_json.count());
    for ([_][]const u8{ "UUIDComponent", "NameComponent", "TransformComponent", "TmplRefComponent" }) |key| {
        try std.testing.expect(shell_json.contains(key));
    }

    //and loads back as the same shell, still unfilled, pointing at the same template
    const loaded_scene = try world.GameWorld().mSManager.CreateBlankScene(engine_context);
    try TextSerializer.DeserializeECSObj(engine_context, loaded_scene, level_path);
    const loaded_entities = try loaded_scene.GetEntityGroup(engine_context.FrameAllocator(), .{ .Component = EntitySceneComponent });
    try std.testing.expectEqual(@as(usize, 1), loaded_entities.items.len);
    const loaded_goblin = loaded_scene.GetEntity(loaded_entities.items[0]);
    try ExpectShell(loaded_goblin, goblin.GetUUID(), "Goblin");
    try std.testing.expectEqual(goblin.GetComponent(TmplRefComponent).?.mTmpl.mID, loaded_goblin.GetComponent(TmplRefComponent).?.mTmpl.mID);
}

test "making a scene a template leaves a shell that keeps its stack slot" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const level = try world.GameWorld().NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const hud = try world.GameWorld().NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    try SetName(engine_context, hud, "HUD");
    const button = try hud.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try button.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    _ = try hud.AddComponent(engine_context, SpawnPossComponent{ .mEntityRef = button });
    const hud_uuid = hud.GetUUID();

    try hud.MakeTmpl(engine_context, try world.TmpPath("HUD.imsc"), .Eng);
    try world.EndFrame(world.GameWorld());

    try ExpectShell(hud, hud_uuid, "HUD");
    try std.testing.expectEqual(.OverlayLayer, hud.GetComponent(SceneComponent).?.mLayerType);
    try std.testing.expect(!hud.HasComponent(SpawnPossComponent));
    try std.testing.expect(!button.IsActive());
    const hud_entities = try hud.GetEntityGroup(engine_context.FrameAllocator(), .{ .Component = EntitySceneComponent });
    try std.testing.expectEqual(@as(usize, 0), hud_entities.items.len);
    //still in the stack where it was
    try std.testing.expectEqual(@as(usize, 2), world.GameWorld().mSManager.mNumofLayers);
    try std.testing.expectEqual(@as(usize, 0), level.GetComponent(StackPosComponent).?.mPosition);
    try std.testing.expectEqual(@as(usize, 1), hud.GetComponent(StackPosComponent).?.mPosition);

    //spawning from it gives the entities back
    const copy = try world.GameWorld().Spawn(Scene, engine_context, hud.GetComponent(TmplRefComponent).?.mTmpl);
    const copy_entities = try copy.GetEntityGroup(engine_context.FrameAllocator(), .{ .Component = EntitySceneComponent });
    try std.testing.expectEqual(@as(usize, 2), copy_entities.items.len);
    try std.testing.expect(copy.HasComponent(SpawnPossComponent));
}

test "making a player a template strips its components and children down to the shell" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const player = try world.GameWorld().CreatePlayer(engine_context, .{
        .bAddNameComponent = true,
        .bAddUUIDComponent = true,
        .bAddPossessComponent = true,
        .bAddMicComponent = false,
        .bAddRenderComponent = false,
    });
    try SetName(engine_context, player, "Player One");
    _ = try player.AddComponent(engine_context, MicComponent{});
    const child = try player.CreateChild(engine_context, .Entity, Player.DefaultConfig);
    const player_uuid = player.GetUUID();

    try player.MakeTmpl(engine_context, try world.TmpPath("Player One.impl"), .Eng);
    try world.EndFrame(world.GameWorld());

    try ExpectShell(player, player_uuid, "Player One");
    try std.testing.expect(!player.HasComponent(PossessComponent));
    try std.testing.expect(!player.HasComponent(MicComponent));
    try std.testing.expect(!child.IsActive());

    const copy = try world.GameWorld().Spawn(Player, engine_context, player.GetComponent(TmplRefComponent).?.mTmpl);
    try std.testing.expect(copy.HasComponent(PossessComponent));
    try std.testing.expect(copy.HasComponent(MicComponent));
    try std.testing.expect(FirstChild(copy).IsActive());
}

test "making a game context a template strips its components and children down to the shell" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const game_context = try world.GameWorld().CreateGameContext(engine_context, GameContext.DefaultConfig);
    try SetName(engine_context, game_context, "Deathmatch");
    _ = try game_context.AddComponent(engine_context, AttribComponent{ .mData = .{ .float32 = 2.5 } });
    const round = try game_context.CreateChild(engine_context, .Entity, GameContext.DefaultConfig);
    const game_context_uuid = game_context.GetUUID();

    try game_context.MakeTmpl(engine_context, try world.TmpPath("Deathmatch.imgc"), .Eng);
    try world.EndFrame(world.GameWorld());

    try ExpectShell(game_context, game_context_uuid, "Deathmatch");
    try std.testing.expect(!game_context.HasComponent(AttribComponent));
    try std.testing.expect(!round.IsActive());

    const copy = try world.GameWorld().Spawn(GameContext, engine_context, game_context.GetComponent(TmplRefComponent).?.mTmpl);
    try std.testing.expectEqual(@as(f32, 2.5), copy.GetComponent(AttribComponent).?.mData.float32);
    try std.testing.expect(FirstChild(copy).IsActive());
}

test "an object that is already a copy can not be made a template" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const scene = try world.GameWorld().NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const goblin = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    try goblin.MakeTmpl(engine_context, try world.TmpPath("Goblin.imen"), .Eng);
    try std.testing.expectError(error.AlreadyATmplCopy, goblin.MakeTmpl(engine_context, try world.TmpPath("Goblin2.imen"), .Eng));
}

//===================================== Template windows =====================================

/// Opens the template in a window, checks it landed in the template editing world with its root selected and its tree
/// under it, then closes the window and checks the tree and the window's handle reference are gone
fn OpenAndClose(world: *TestWorld, tmpl: AssetHandle, comptime obj_t: type) !void {
    const engine_context = world.mEngineContext;
    const refs_before_open = world.Refs(tmpl);
    //the window takes over a reference of its own, like the one OpenTmplEvent carries
    tmpl.RetainAsset();
    var panel = try TmplEditPanel.Open(engine_context, tmpl);

    const root: obj_t = switch (panel.mRoot) {
        inline else => |object| if (@TypeOf(object) == obj_t) object else return error.WrongRootType,
    };
    try std.testing.expect(root.mManager == &engine_context.mTmplEditWorld);
    try std.testing.expectEqual(root.mID, switch (panel.mSelected.?) {
        inline else => |object| object.mID,
    });
    const child = FirstChild(root);

    try panel.Close(engine_context);
    try world.EndFrame(&engine_context.mTmplEditWorld);
    try std.testing.expect(!root.IsActive());
    try std.testing.expect(!child.IsActive());
    try std.testing.expectEqual(refs_before_open, world.Refs(tmpl));
}

test "a template window opens each type in the template editing world and closes it again" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const scene = try world.TmplWorld().NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const goblin = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try goblin.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    try OpenAndClose(world, try world.SaveTmpl(goblin, "goblin.imen"), Entity);

    const hud = try world.TmplWorld().NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    _ = try hud.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try hud.CreateChild(engine_context, .Entity, Scene.DefaultConfig);
    const hud_tmpl = try world.SaveTmpl(hud, "hud.imsc");
    //a scene template takes a stack slot in the editing world while it is open, next to the entity templates' scene
    hud_tmpl.RetainAsset();
    var hud_panel = try TmplEditPanel.Open(engine_context, hud_tmpl);
    try std.testing.expectEqual(@as(usize, 2), engine_context.mTmplEditWorld.mSManager.mNumofLayers);
    try hud_panel.Close(engine_context);
    try world.EndFrame(&engine_context.mTmplEditWorld);
    try std.testing.expectEqual(@as(usize, 1), engine_context.mTmplEditWorld.mSManager.mNumofLayers);
    try OpenAndClose(world, hud_tmpl, Scene);

    const player = try world.TmplWorld().CreatePlayer(engine_context, Player.DefaultConfig);
    _ = try player.CreateChild(engine_context, .Entity, Player.DefaultConfig);
    try OpenAndClose(world, try world.SaveTmpl(player, "player_one.impl"), Player);

    const game_context = try world.TmplWorld().CreateGameContext(engine_context, GameContext.DefaultConfig);
    _ = try game_context.CreateChild(engine_context, .Entity, GameContext.DefaultConfig);
    try OpenAndClose(world, try world.SaveTmpl(game_context, "deathmatch.imgc"), GameContext);
}

test "saving a template window writes the edits to its file, and the next spawn uses them" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const tmpl_scene = try world.TmplWorld().NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const goblin = try tmpl_scene.CreateEntity(engine_context, Entity.DefaultConfig);
    const sword = try goblin.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    try SetName(engine_context, sword, "Sword");
    const tmpl = try world.SaveTmpl(goblin, "goblin.imen");

    const scene = try world.GameWorld().NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const before = try scene.Spawn(engine_context, tmpl);
    try ExpectName(FirstChild(before), "Sword");

    tmpl.RetainAsset();
    var panel = try TmplEditPanel.Open(engine_context, tmpl);
    try SetName(engine_context, FirstChild(panel.mRoot.entity), "Axe");
    try panel.Save(engine_context);

    //what the editor's frame does: the asset manager sees the file changed and drops its loaded copy
    try engine_context.mAssetManager.OnUpdate(engine_context);
    try engine_context.mAssetManager.ProcessDestroyedAssets(engine_context);
    try world.EndFrame(&engine_context.mAssetWorld);

    const after = try scene.Spawn(engine_context, tmpl);
    try ExpectName(FirstChild(after), "Axe");
    //a copy spawned before the edit keeps what it was spawned with
    try ExpectName(FirstChild(before), "Sword");

    try panel.Close(engine_context);
}

test "a file that is not a template can not be opened in a template window" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    var texture = try engine_context.mAssetManager.GetAssetHandle(engine_context, .{ .File = .{ .rel_path = TEXTURE_PATH, .path_type = .Eng } });
    defer texture.ReleaseAsset();
    try std.testing.expectError(error.NotATmplFile, TmplEditPanel.Open(engine_context, texture));
}
