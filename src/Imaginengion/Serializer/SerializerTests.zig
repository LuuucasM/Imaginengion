//! Saves each object type (entity, scene, player, game context) to a file and reads it back into a blank
//! object, the way every loader does. No window, renderer or asset manager needed, so only components that
//! don't touch those are used. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../Core/EngineContext.zig");
const TextSerializer = @import("TextSerializer.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const Player = @import("../ECSObjects/Player.zig");
const GameContext = @import("../ECSObjects/GameContext.zig");

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const TransformComponent = EntityComponents.TransformComponent;
const EntitySceneComponent = EntityComponents.EntitySceneComponent;
const SceneComponents = @import("../ECSComponents/SComponents.zig");
const SceneComponent = SceneComponents.SceneComponent;
const StackPosComponent = SceneComponents.StackPosComponent;
const PlayerComponents = @import("../ECSComponents/PComponents.zig");
const MicComponent = PlayerComponents.MicComponent;
const PossessComponent = PlayerComponents.PossessComponent;
const AttribComponent = @import("../ECSComponents/GCComponents.zig").AttribComponent;

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
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        engine_context.mEditorWorld.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
        self.mTmpDir.cleanup();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    /// A path in this test's temporary folder, relative to the working directory like the serializer expects
    fn FilePath(self: *TestWorld, file_name: []const u8) ![]const u8 {
        return std.fmt.allocPrint(self.mEngineContext.FrameAllocator(), ".zig-cache/tmp/{s}/{s}", .{ self.mTmpDir.sub_path, file_name });
    }
};

fn ExpectName(object: anytype, expected: []const u8) !void {
    try std.testing.expectEqualStrings(expected, object.GetName());
}

test "an entity tree round trips, children included" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const goblin = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    try goblin.GetComponent(EntityComponents.NameComponent).?.mName.replaceRange(engine_context.EngineAllocator(), 0, goblin.GetName().len, "Goblin");
    try goblin.SetTranslation(engine_context, .{ .x = 4.0, .y = 5.0, .z = 6.0 });
    const sword = try goblin.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    try sword.GetComponent(EntityComponents.NameComponent).?.mName.replaceRange(engine_context.EngineAllocator(), 0, sword.GetName().len, "Sword");
    _ = try sword.CreateChild(engine_context, .Entity, Entity.DefaultConfig);

    const path = try world.FilePath("goblin.imen");
    try TextSerializer.SerializeECSObject(engine_context, goblin, path);

    const other_scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const loaded = try other_scene.CreateEntity(engine_context, Entity.BlankConfig);
    try TextSerializer.DeserializeECSObj(engine_context, loaded, path);

    try ExpectName(loaded, "Goblin");
    try std.testing.expectEqual(goblin.GetUUID(), loaded.GetUUID());
    try std.testing.expectEqual(@as(f32, 5.0), loaded.GetComponent(TransformComponent).?.GetTranslation().y);

    var child_iter = loaded.GetIterator(.Child);
    const loaded_sword = child_iter.next().?;
    try std.testing.expect(child_iter.next() == null);
    try ExpectName(loaded_sword, "Sword");
    //children join their parent's scene
    try std.testing.expectEqual(other_scene.mID, loaded_sword.GetComponent(EntitySceneComponent).?.mScene.mID);

    var grandchild_iter = loaded_sword.GetIterator(.Child);
    try std.testing.expect(grandchild_iter.next() != null);
}

test "a scene round trips with its entities and takes its slot in the scene stack" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene_manager = &engine_context.mEditorWorld.mSManager;

    const game_layer = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const overlay = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    overlay.GetComponent(SceneComponent).?.mOverlayScaleMode = .ConstantPixelSize;
    const button = try overlay.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try button.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    _ = try overlay.CreateEntity(engine_context, Entity.DefaultConfig);

    const path = try world.FilePath("hud.imsc");
    try TextSerializer.SerializeECSObject(engine_context, overlay, path);

    const loaded = try scene_manager.CreateBlankScene(engine_context);
    try TextSerializer.DeserializeECSObj(engine_context, loaded, path);

    const scene_component = loaded.GetComponent(SceneComponent).?;
    try std.testing.expectEqual(.OverlayLayer, scene_component.mLayerType);
    try std.testing.expectEqual(.ConstantPixelSize, scene_component.mOverlayScaleMode);
    try std.testing.expectEqual(overlay.GetUUID(), loaded.GetUUID());

    //slotted in above the game layer and the first overlay, the same as a new overlay would be
    try std.testing.expectEqual(@as(usize, 3), scene_manager.mNumofLayers);
    try std.testing.expectEqual(@as(usize, 0), game_layer.GetComponent(StackPosComponent).?.mPosition);
    try std.testing.expectEqual(@as(usize, 2), loaded.GetComponent(StackPosComponent).?.mPosition);

    //both top level entities, and the child under the first, belong to the loaded scene
    const loaded_entities = try loaded.GetEntityGroup(engine_context.FrameAllocator(), .{ .Component = EntitySceneComponent });
    try std.testing.expectEqual(@as(usize, 3), loaded_entities.items.len);
}

test "a player round trips, children included" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const player = try engine_context.mEditorWorld.CreatePlayer(engine_context, .{
        .bAddNameComponent = true,
        .bAddUUIDComponent = true,
        .bAddPossessComponent = true,
        .bAddMicComponent = false,
        .bAddRenderComponent = false,
    });
    _ = try player.AddComponent(engine_context, MicComponent{});
    _ = try player.CreateChild(engine_context, .Entity, Player.DefaultConfig);

    const path = try world.FilePath("player_one.impl");
    try TextSerializer.SerializeECSObject(engine_context, player, path);

    const loaded = try engine_context.mEditorWorld.CreatePlayer(engine_context, Player.BlankConfig);
    try TextSerializer.DeserializeECSObj(engine_context, loaded, path);

    try ExpectName(loaded, "New Player");
    try std.testing.expectEqual(player.GetUUID(), loaded.GetUUID());
    try std.testing.expect(loaded.HasComponent(PossessComponent));
    try std.testing.expect(loaded.HasComponent(MicComponent));

    var child_iter = loaded.GetIterator(.Child);
    const loaded_child = child_iter.next().?;
    try ExpectName(loaded_child, "New Player");
}

test "a game context round trips, children included" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const game_context = try engine_context.mEditorWorld.CreateGameContext(engine_context, GameContext.DefaultConfig);
    _ = try game_context.AddComponent(engine_context, AttribComponent{ .mData = .{ .float32 = 2.5 } });
    const round = try game_context.CreateChild(engine_context, .Entity, GameContext.DefaultConfig);
    _ = try round.AddComponent(engine_context, AttribComponent{ .mData = .{ .bool = true } });

    const path = try world.FilePath("deathmatch.imgc");
    try TextSerializer.SerializeECSObject(engine_context, game_context, path);

    const loaded = try engine_context.mEditorWorld.CreateGameContext(engine_context, GameContext.BlankConfig);
    try TextSerializer.DeserializeECSObj(engine_context, loaded, path);

    try ExpectName(loaded, "New Game Context");
    try std.testing.expectEqual(game_context.GetUUID(), loaded.GetUUID());
    try std.testing.expectEqual(@as(f32, 2.5), loaded.GetComponent(AttribComponent).?.mData.float32);

    var child_iter = loaded.GetIterator(.Child);
    const loaded_round = child_iter.next().?;
    try std.testing.expect(loaded_round.GetComponent(AttribComponent).?.mData.bool);
}
