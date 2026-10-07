//! WorldManager.Copy, the copy play mode runs on: object ids carry over, and every object handle held in a
//! copied component points at the copy rather than at the world it was copied from.
//! No window or renderer needed. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const WorldManager = @import("../../Core/WorldManager.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const Player = @import("../../ECSObjects/Player.zig");

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const PlayerSlotComponent = EntityComponents.PlayerSlotComponent;
const EntitySceneComponent = EntityComponents.EntitySceneComponent;
const PossessComponent = @import("../../ECSComponents/PComponents.zig").PossessComponent;
const SpawnPossComponent = @import("../../ECSComponents/SComponents.zig").SpawnPossComponent;

const TestWorlds = struct {
    mEngineContext: *EngineContext,

    fn Init() !*TestWorlds {
        const self = try std.heap.page_allocator.create(TestWorlds);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        //UUIDs are drawn from the context's Io, which forwards to this
        engine_context._Internal.ThreadedIO = std.Io.Threaded.init(engine_context._Internal.EngineGPA.allocator(), .{
            .concurrent_limit = .nothing,
            .async_limit = .nothing,
        });
        try engine_context.mGameWorld.Init(engine_context.EngineAllocator());
        try engine_context.mSimulateWorld.Init(engine_context.EngineAllocator());
        return self;
    }

    fn Deinit(self: *TestWorlds) void {
        const engine_context = self.mEngineContext;
        engine_context.mSimulateWorld.Deinit(engine_context);
        engine_context.mGameWorld.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }
};

/// A scene with one entity a player possesses and the scene spawns from: every kind of handle a
/// world component holds, across three of the four managers
const PossessSetup = struct {
    mScene: Scene,
    mEntity: Entity,
    mPlayer: Player,

    fn Build(engine_context: *EngineContext, world: *WorldManager) !PossessSetup {
        const scene = try world.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
        const entity = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
        _ = try entity.AddComponent(engine_context, PlayerSlotComponent{});

        var player_config = Player.DefaultConfig;
        player_config.bAddPossessComponent = true;
        const player = try world.CreatePlayer(engine_context, player_config);
        player.Possess(entity);

        _ = try scene.AddComponent(engine_context, SpawnPossComponent{ .mEntityRef = entity });

        return .{ .mScene = scene, .mEntity = entity, .mPlayer = player };
    }
};

test "a copied world's object handles point at the copy, not the world it came from" {
    const worlds = try TestWorlds.Init();
    defer worlds.Deinit();
    const engine_context = worlds.mEngineContext;
    const game_world = &engine_context.mGameWorld;
    const sim_world = &engine_context.mSimulateWorld;

    const setup = try PossessSetup.Build(engine_context, game_world);

    try game_world.Copy(engine_context, sim_world);

    //the same ids, looked up in the copy
    const sim_entity = sim_world.GetEntity(setup.mEntity.mID);
    const sim_player = sim_world.GetPlayer(setup.mPlayer.mID);
    const sim_scene = sim_world.GetScene(setup.mScene.mID);

    const possessed = sim_player.GetComponent(PossessComponent).?.mPossessedEntity;
    try std.testing.expectEqual(setup.mEntity.mID, possessed.mID);
    try std.testing.expectEqual(sim_world, possessed.mManager);

    const slot_player = sim_entity.GetComponent(PlayerSlotComponent).?.mPlayerEntity;
    try std.testing.expectEqual(setup.mPlayer.mID, slot_player.mID);
    try std.testing.expectEqual(sim_world, slot_player.mManager);

    const spawn_ref = sim_scene.GetComponent(SpawnPossComponent).?.mEntityRef;
    try std.testing.expectEqual(setup.mEntity.mID, spawn_ref.mID);
    try std.testing.expectEqual(sim_world, spawn_ref.mManager);

    const entity_scene = sim_entity.GetComponent(EntitySceneComponent).?.mScene;
    try std.testing.expectEqual(setup.mScene.mID, entity_scene.mID);
    try std.testing.expectEqual(sim_world, entity_scene.mManager);
}

test "a copied world's overlays measure the screen the way the original's do" {
    const worlds = try TestWorlds.Init();
    defer worlds.Deinit();
    const engine_context = worlds.mEngineContext;

    engine_context.mGameWorld.mOverlayScaleMode = .ConstantPixelSize;
    try engine_context.mGameWorld.Copy(engine_context, &engine_context.mSimulateWorld);
    try std.testing.expectEqual(.ConstantPixelSize, engine_context.mSimulateWorld.mOverlayScaleMode);
}

test "copying a world leaves the original's object handles on the original" {
    const worlds = try TestWorlds.Init();
    defer worlds.Deinit();
    const engine_context = worlds.mEngineContext;
    const game_world = &engine_context.mGameWorld;
    const sim_world = &engine_context.mSimulateWorld;

    const setup = try PossessSetup.Build(engine_context, game_world);

    try game_world.Copy(engine_context, sim_world);

    try std.testing.expectEqual(game_world, setup.mPlayer.GetComponent(PossessComponent).?.mPossessedEntity.mManager);
    try std.testing.expectEqual(game_world, setup.mEntity.GetComponent(PlayerSlotComponent).?.mPlayerEntity.mManager);
    try std.testing.expectEqual(game_world, setup.mScene.GetComponent(SpawnPossComponent).?.mEntityRef.mManager);
    try std.testing.expectEqual(game_world, setup.mEntity.GetComponent(EntitySceneComponent).?.mScene.mManager);
}

test "a copied player's render view is built from the copy's entities" {
    const worlds = try TestWorlds.Init();
    defer worlds.Deinit();
    const engine_context = worlds.mEngineContext;
    const game_world = &engine_context.mGameWorld;
    const sim_world = &engine_context.mSimulateWorld;

    const setup = try PossessSetup.Build(engine_context, game_world);

    try game_world.Copy(engine_context, sim_world);

    //what the play viewport does: follow the simulate world's player to the entity it possesses.
    //moving that entity in the copy has to be what the copy's player sees
    const sim_player = sim_world.GetPlayer(setup.mPlayer.mID);
    const possessed = sim_player.GetComponent(PossessComponent).?.mPossessedEntity;
    try std.testing.expect(possessed.IsActive());

    const sim_entity = sim_world.GetEntity(setup.mEntity.mID);
    try std.testing.expectEqual(sim_entity.GetComponent(PlayerSlotComponent).?, possessed.GetComponent(PlayerSlotComponent).?);
}
