//! Starting a game from a project's entries (Programs/GameProgram.zig): the entry scene loaded into the game world and
//! the entry player and game mode spawned there. No window or renderer needed. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const TextSerializer = @import("../../Serializer/TextSerializer.zig");
const GameProgram = @import("../../Programs/GameProgram.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const Player = @import("../../ECSObjects/Player.zig");
const GameContext = @import("../../ECSObjects/GameContext.zig");

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const EntitySceneComponent = EntityComponents.EntitySceneComponent;
const NameComponent = EntityComponents.NameComponent;
const SceneComponent = @import("../../ECSComponents/SComponents.zig").SceneComponent;
const PossessComponent = @import("../../ECSComponents/PComponents.zig").PossessComponent;
const GCNameComponent = @import("../../ECSComponents/GCComponents.zig").NameComponent;

const TestEngine = struct {
    mEngineContext: *EngineContext,
    mTmpDir: std.testing.TmpDir,

    fn Init() !*TestEngine {
        const self = try std.heap.page_allocator.create(TestEngine);
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
        try engine_context.mAssetWorld.Init(engine_allocator);
        engine_context.mAssetEntityScene = try engine_context.mAssetWorld.NewScene(engine_context, .GameLayer, Scene.BlankConfig);
        try engine_context.mUIManager.Init(engine_allocator);
        //the audio settings are one of the project's settings owners
        try engine_context.mAudioManager.InitMixer(engine_context);
        //the entries are made in here and saved, the game starts in the game world
        try engine_context.mSimulateWorld.Init(engine_allocator);
        try engine_context.mGameWorld.Init(engine_allocator);
        return self;
    }

    fn Deinit(self: *TestEngine) void {
        const engine_context = self.mEngineContext;
        const engine_allocator = engine_context.EngineAllocator();
        //everything that holds asset handles goes while the asset manager is still alive, as in EngineContext.DeInit
        engine_context.mGameWorld.Deinit(engine_context);
        engine_context.mSimulateWorld.Deinit(engine_context);
        engine_context.mAssetWorld.clearAndFree(engine_context, .All);
        engine_context.mSerializer.Deinit(engine_allocator);
        engine_context.mAudioManager.DeinitMixer(engine_context);
        engine_context.mProject.Deinit(engine_context);
        //the asset manager, minus the default assets Init never set up and the working directory handle it does not own
        const asset_manager = &engine_context.mAssetManager;
        asset_manager.mECSManager.Deinit(engine_context);
        asset_manager.mUUIDToWorldID.deinit(engine_allocator);
        asset_manager.mEventManager.Deinit(engine_allocator);
        asset_manager.mCWDPath.deinit(engine_allocator);
        engine_context.mAssetWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);

        _ = engine_context._Internal.EngineGPA.deinit();
        self.mTmpDir.cleanup();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    /// Saves `object` into the project folder and makes it the project's `entry`
    fn SaveEntry(self: *TestEngine, object: anytype, entry: @import("../../Core/Project.zig").Entry, file_name: []const u8) !void {
        const engine_context = self.mEngineContext;
        const abs_path = try engine_context.mProject.GetAbsPath(engine_context.FrameAllocator(), file_name);
        try TextSerializer.SerializeECSObject(engine_context, object, abs_path);
        try engine_context.mProject.SetEntry(engine_context, entry, abs_path);
    }
};

fn SetName(engine_context: *EngineContext, object: anytype, comptime name_t: type, name: []const u8) !void {
    const name_list = &object.GetComponent(name_t).?.mName;
    name_list.clearRetainingCapacity();
    try name_list.appendSlice(engine_context.EngineAllocator(), name);
}

test "starting a game loads the entry scene and spawns the entry player and game mode into the game world" {
    const engine = try TestEngine.Init();
    defer engine.Deinit();
    const engine_context = engine.mEngineContext;
    const frame_allocator = engine_context.FrameAllocator();

    const project_folder = try engine.mTmpDir.dir.realPathFileAlloc(engine_context.Io(), ".", frame_allocator);
    try engine_context.mProject.New(engine_context, project_folder);

    const level = try engine_context.mSimulateWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const camera = try level.CreateEntity(engine_context, Entity.DefaultConfig);
    try SetName(engine_context, camera, NameComponent, "Camera");
    try engine.SaveEntry(level, .Scene, "Level.imsc");

    const player = try engine_context.mSimulateWorld.CreatePlayer(engine_context, .{
        .bAddNameComponent = true,
        .bAddUUIDComponent = true,
        .bAddPossessComponent = true,
        .bAddMicComponent = false,
        .bAddRenderComponent = false,
    });
    try engine.SaveEntry(player, .Player, "Hero.impl");

    const game_mode = try engine_context.mSimulateWorld.CreateGameContext(engine_context, GameContext.DefaultConfig);
    try SetName(engine_context, game_mode, GCNameComponent, "Rules");
    try engine.SaveEntry(game_mode, .GameContext, "Rules.imgc");

    try GameProgram.StartGame(engine_context);
    const game_world = &engine_context.mGameWorld;

    const scene_ids = try game_world.GetSceneGroup(frame_allocator, .{ .Component = SceneComponent });
    try std.testing.expectEqual(@as(usize, 1), scene_ids.items.len);
    const entity_ids = try game_world.GetScene(scene_ids.items[0]).GetEntityGroup(frame_allocator, .{ .Component = EntitySceneComponent });
    try std.testing.expectEqual(@as(usize, 1), entity_ids.items.len);
    try std.testing.expectEqualStrings("Camera", game_world.GetEntity(entity_ids.items[0]).GetName());

    //possessing something is left to the game's scripts
    const player_ids = try game_world.GetPlayerGroup(frame_allocator, .{ .Component = PossessComponent });
    try std.testing.expectEqual(@as(usize, 1), player_ids.items.len);
    try std.testing.expect(!game_world.GetPlayer(player_ids.items[0]).GetComponent(PossessComponent).?.mPossessedEntity.IsActive());

    const game_mode_ids = try game_world.GetGameContextGroup(frame_allocator, .{ .Component = GCNameComponent });
    try std.testing.expectEqual(@as(usize, 1), game_mode_ids.items.len);
    try std.testing.expectEqualStrings("Rules", game_world.GetGameContext(game_mode_ids.items[0]).GetName());
}
