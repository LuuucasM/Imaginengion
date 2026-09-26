//! Loads each object asset type (entity, scene, player, game context) from a file into the asset world and
//! unloads it again, the way the asset manager does on first use and on a file change. Calls Init/Deinit
//! directly since the asset manager needs a window. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const TextSerializer = @import("../../Serializer/TextSerializer.zig");
const Assets = @import("../AComponents.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const Player = @import("../../ECSObjects/Player.zig");
const GameContext = @import("../../ECSObjects/GameContext.zig");

const EntitySceneComponent = @import("../EComponents.zig").EntitySceneComponent;
const AttribComponent = @import("../GCComponents.zig").AttribComponent;

const EEventData = @import("../../Events/EManagerData.zig");
const GCEventData = @import("../../Events/GCManagerData.zig");
const PEventData = @import("../../Events/PManagerData.zig");
const SEventData = @import("../../Events/SManagerData.zig");
const ECSEventData = @import("../../Events/ECSEventData.zig");

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
        //UUIDs and file reads/writes go through the context's Io, which forwards to this
        engine_context._Internal.ThreadedIO = std.Io.Threaded.init(engine_context._Internal.EngineGPA.allocator(), .{
            .concurrent_limit = .nothing,
            .async_limit = .nothing,
        });
        try engine_context.mEditorWorld.Init(engine_context.EngineAllocator());
        //the same asset world setup as EngineContext.Init
        try engine_context.mAssetWorld.Init(engine_context.EngineAllocator());
        engine_context.mAssetEntityScene = try engine_context.mAssetWorld.NewScene(engine_context, .GameLayer, Scene.BlankConfig);
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mAssetWorld.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
        self.mTmpDir.cleanup();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    /// A path in this test's temporary folder, relative to the working directory like the serializer expects
    fn FilePath(self: *TestWorld, file_name: []const u8) ![]const u8 {
        return std.fmt.allocPrint(self.mEngineContext.FrameAllocator(), ".zig-cache/tmp/{s}/{s}", .{ self.mTmpDir.sub_path, file_name });
    }

    /// The asset world's part of EditorProgram.OnUpdate's end of frame
    fn EndFrame(self: *TestWorld) !void {
        const engine_context = self.mEngineContext;
        const world = &engine_context.mAssetWorld;
        var callback_list: std.DoublyLinkedList = .{};
        try world.ProcessEvents(SEventData, .EndOfFrame, engine_context, &callback_list);
        try world.ProcessEvents(GCEventData, .EndOfFrame, engine_context, &callback_list);
        try world.ProcessEvents(PEventData, .EndOfFrame, engine_context, &callback_list);
        try world.ProcessEvents(EEventData, .EndOfFrame, engine_context, &callback_list);
        try world.ProcessEvents(ECSEventData, .EndOfFrame, engine_context, &callback_list);
    }
};

/// Saves `original` (made in the editor world), loads it as an asset and checks it landed in the asset world
/// with its child and UUID. Returns the asset so the per-type test can check what is special about its type
/// before calling Unload.
fn Load(comptime AssetT: type, world: *TestWorld, original: anytype, file_name: []const u8) !AssetT {
    const obj_t = @TypeOf(original);
    const engine_context = world.mEngineContext;

    const path = try world.FilePath(file_name);
    try TextSerializer.SerializeECSObject(engine_context, original, path);

    var asset: AssetT = .{};
    try asset.Init(engine_context, path, file_name, undefined);

    const loaded = asset.mObject;
    try std.testing.expect(loaded.IsActive());
    try std.testing.expect(loaded.mManager == &engine_context.mAssetWorld);
    try std.testing.expectEqualStrings(original.GetName(), loaded.GetName());
    try std.testing.expectEqual(loaded.mID, engine_context.mAssetWorld.GetObjectByUUID(obj_t, original.GetUUID()).?.mID);

    var child_iter = loaded.GetIterator(.Child);
    try std.testing.expect(child_iter.next() != null);

    //the editor world's original is untouched and still owns its UUID there
    try std.testing.expectEqual(original.mID, engine_context.mEditorWorld.GetObjectByUUID(obj_t, original.GetUUID()).?.mID);
    return asset;
}

fn Unload(world: *TestWorld, asset: anytype) !void {
    const engine_context = world.mEngineContext;
    const loaded = asset.mObject;
    const obj_t = @TypeOf(loaded);
    const uuid = loaded.GetUUID();

    var child_iter = loaded.GetIterator(.Child);
    const child = child_iter.next().?;

    asset.Deinit(engine_context);
    try world.EndFrame();

    try std.testing.expect(!loaded.IsActive());
    try std.testing.expect(!child.IsActive());
    try std.testing.expect(engine_context.mAssetWorld.GetObjectByUUID(obj_t, uuid) == null);

    //unloading again, like the asset manager's shutdown does after the world was emptied, does nothing
    asset.Deinit(engine_context);
}

test "an entity asset loads into the asset world's entity scene and unloads with its children" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const goblin = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try goblin.CreateChild(engine_context, .Entity, Entity.DefaultConfig);

    var asset = try Load(Assets.EntityAsset, world, goblin, "goblin.imen");
    try std.testing.expectEqual(engine_context.mAssetEntityScene.mID, asset.mObject.GetComponent(EntitySceneComponent).?.mScene.mID);
    try Unload(world, &asset);
}

test "a scene asset loads with its entities and unloads them along with it" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const asset_scenes = &engine_context.mAssetWorld.mSManager;

    const hud = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    const button = try hud.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try button.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    //a scene child too, so Load has one to find
    _ = try hud.CreateChild(engine_context, .Entity, Scene.DefaultConfig);

    var asset = try Load(Assets.SceneAsset, world, hud, "hud.imsc");
    const loaded_entities = try asset.mObject.GetEntityGroup(engine_context.FrameAllocator(), .{ .Component = EntitySceneComponent });
    try std.testing.expectEqual(@as(usize, 2), loaded_entities.items.len);
    //the entity scene plus the loaded one
    try std.testing.expectEqual(@as(usize, 2), asset_scenes.mNumofLayers);

    const loaded_button = asset.mObject.GetEntity(loaded_entities.items[0]);
    try Unload(world, &asset);

    try std.testing.expect(!loaded_button.IsActive());
    try std.testing.expectEqual(@as(usize, 1), asset_scenes.mNumofLayers);
}

test "a player asset loads into the asset world and unloads with its children" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const player = try engine_context.mEditorWorld.CreatePlayer(engine_context, Player.DefaultConfig);
    _ = try player.CreateChild(engine_context, .Entity, Player.DefaultConfig);

    var asset = try Load(Assets.PlayerAsset, world, player, "player_one.impl");
    try Unload(world, &asset);
}

test "a game context asset loads into the asset world and unloads with its children" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const game_context = try engine_context.mEditorWorld.CreateGameContext(engine_context, GameContext.DefaultConfig);
    _ = try game_context.AddComponent(engine_context, AttribComponent{ .mData = .{ .int32 = -3 } });
    _ = try game_context.CreateChild(engine_context, .Entity, GameContext.DefaultConfig);

    var asset = try Load(Assets.GCAsset, world, game_context, "deathmatch.imgc");
    try std.testing.expectEqual(@as(i32, -3), asset.mObject.GetComponent(AttribComponent).?.mData.int32);
    try Unload(world, &asset);
}
