//! WorldManager.LoadOrGet and Scene.LoadOrGetEntity: the first call loads the file, later ones hand back what it
//! loaded instead of a second copy. No window or renderer needed. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const TextSerializer = @import("../../Serializer/TextSerializer.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");

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
        //the UI and audio settings are among the project's settings owners, which mProject.New fills
        try engine_context.mUIManager.Init(engine_allocator);
        try engine_context.mAudioManager.InitMixer(engine_context);
        //the files are made in the simulate world and loaded into the game world, which starts without them
        try engine_context.mSimulateWorld.Init(engine_allocator);
        try engine_context.mGameWorld.Init(engine_allocator);

        const project_folder = try self.mTmpDir.dir.realPathFileAlloc(engine_context.Io(), ".", engine_context.FrameAllocator());
        try engine_context.mProject.New(engine_context, project_folder);
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

    /// Saves `object` into the project folder as `file_name`, which is then its path under .Prj
    fn Save(self: *TestEngine, object: anytype, file_name: []const u8) !void {
        const engine_context = self.mEngineContext;
        const abs_path = try engine_context.mProject.GetAbsPath(engine_context.FrameAllocator(), file_name);
        try TextSerializer.SerializeECSObject(engine_context, object, abs_path);
    }
};

test "LoadOrGet loads a scene the first time and hands back the same scene after" {
    const engine = try TestEngine.Init();
    defer engine.Deinit();
    const engine_context = engine.mEngineContext;

    const pause_menu = try engine_context.mSimulateWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    try engine.Save(pause_menu, "PauseMenu.imsc");
    const uuid = pause_menu.GetUUID();

    const world = &engine_context.mGameWorld;
    try std.testing.expect(world.GetObjectByUUID(Scene, uuid) == null);

    const first = try world.LoadOrGet(Scene, engine_context, uuid, "PauseMenu.imsc", .Prj);
    try std.testing.expectEqual(uuid, first.GetUUID());

    const second = try world.LoadOrGet(Scene, engine_context, uuid, "PauseMenu.imsc", .Prj);
    try std.testing.expectEqual(first.mID, second.mID);
}

test "LoadOrGetEntity loads an entity the first time and hands back the same entity after" {
    const engine = try TestEngine.Init();
    defer engine.Deinit();
    const engine_context = engine.mEngineContext;

    const level = try engine_context.mSimulateWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const paddle = try level.CreateEntity(engine_context, Entity.DefaultConfig);
    try engine.Save(paddle, "Paddle.imen");
    const uuid = paddle.GetUUID();

    const game_level = try engine_context.mGameWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    const first = try game_level.LoadOrGetEntity(engine_context, uuid, "Paddle.imen", .Prj);
    try std.testing.expectEqual(uuid, first.GetUUID());

    const second = try game_level.LoadOrGetEntity(engine_context, uuid, "Paddle.imen", .Prj);
    try std.testing.expectEqual(first.mID, second.mID);
}
