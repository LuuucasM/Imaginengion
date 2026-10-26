//! How the engine's ECSs join the systems layer (ECS/Systems.zig): each world registers its four and connects them to
//! each other in its Init, the UI and audio register theirs, and EngineContext.StartUsingWorld connects those two to a
//! world in use. Run with `zig build test-engine`.
const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig");
const WorldManager = @import("../../Core/WorldManager.zig");
const Systems = @import("../../ECS/Systems.zig");
const EManager = @import("../../ECSManagers/EManager.zig");
const SManager = @import("../../ECSManagers/SManager.zig");
const TransformComponent = @import("../../ECSComponents/EComponents.zig").TransformComponent;
const SceneComponent = @import("../../ECSComponents/SComponents.zig").SceneComponent;

/// A context with two worlds, the UI and audio's voices and buses: no window, GPU or sound card
const TestEngine = struct {
    mEngineContext: *EngineContext,

    fn Init() !*TestEngine {
        const self = try std.heap.page_allocator.create(TestEngine);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        //a bus's UUID comes from the context's Io, which forwards to this
        engine_context._Internal.ThreadedIO = std.Io.Threaded.init(engine_context._Internal.EngineGPA.allocator(), .{
            .concurrent_limit = .nothing,
            .async_limit = .nothing,
        });
        try engine_context.mGameWorld.Init(engine_context);
        try engine_context.mEditorWorld.Init(engine_context);
        try engine_context.mUIManager.Init(engine_context);
        try engine_context.mAudioManager.InitMixer(engine_context);
        return self;
    }

    fn Deinit(self: *TestEngine) !void {
        const engine_context = self.mEngineContext;
        engine_context.mGameWorld.Deinit(engine_context);
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mAudioManager.DeinitMixer(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        //everything unregistered, so the layer has let go of its memory too
        const nothing_left = engine_context.mSystems.mNodes.items.len == 0 and engine_context.mSystems.mNodes.capacity == 0;
        const leak_check = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
        try std.testing.expect(nothing_left);
        try std.testing.expect(leak_check == .ok);
    }
};

// a world's four ECSs, as the layer knows them
fn ECSsOf(world: *WorldManager) [4]*anyopaque {
    return .{ &world.mEManager.mECSManager, &world.mGCManager.mECSManager, &world.mPManager.mECSManager, &world.mSManager.mECSManager };
}

test "a world's four ECSs are registered and connected to each other, not to another world's" {
    const engine = try TestEngine.Init();
    defer engine.Deinit() catch unreachable;
    const systems = &engine.mEngineContext.mSystems;
    const game = ECSsOf(&engine.mEngineContext.mGameWorld);
    const editor = ECSsOf(&engine.mEngineContext.mEditorWorld);

    for (game, 0..) |ecs, ecs_ind| {
        try std.testing.expect(systems.IsRegistered(ecs));
        for (game, 0..) |other, other_ind| {
            if (other_ind != ecs_ind) try std.testing.expect(systems.IsConnected(ecs, other));
        }
        for (editor) |other| try std.testing.expect(!systems.IsConnected(ecs, other));
    }
    try std.testing.expect(systems.IsRegistered(&engine.mEngineContext.mUIManager.mECSManager));
    try std.testing.expect(systems.IsRegistered(&engine.mEngineContext.mAudioManager.mECSManager));
}

test "a world in use is connected to the UI and audio until it stops being used" {
    const engine = try TestEngine.Init();
    defer engine.Deinit() catch unreachable;
    const engine_context = engine.mEngineContext;
    const systems = &engine_context.mSystems;
    const ui_ecs = &engine_context.mUIManager.mECSManager;
    const audio_ecs = &engine_context.mAudioManager.mECSManager;

    try engine_context.StartUsingWorld(&engine_context.mGameWorld);
    for (ECSsOf(&engine_context.mGameWorld)) |ecs| {
        try std.testing.expect(systems.IsConnected(ecs, ui_ecs));
        try std.testing.expect(systems.IsConnected(ecs, audio_ecs));
    }
    //only the world in use
    for (ECSsOf(&engine_context.mEditorWorld)) |ecs| try std.testing.expect(!systems.IsConnected(ecs, ui_ecs));

    engine_context.StopUsingWorld(&engine_context.mGameWorld);
    for (ECSsOf(&engine_context.mGameWorld)) |ecs| {
        try std.testing.expect(!systems.IsConnected(ecs, ui_ecs));
        try std.testing.expect(!systems.IsConnected(ecs, audio_ecs));
    }
}

/// What a UI system sees of the worlds while it runs
var transforms_locked_in_game: bool = false;
var scenes_locked_in_game: bool = false;

const ReadsWorldTransforms = struct {
    pub const Name = "ReadsWorldTransforms";
    pub const Reads = &.{Systems.In(EManager.ECSManagerT, TransformComponent)};
    pub const Writes = &.{};

    pub fn Run(engine_context: *EngineContext) void {
        const entity_ecs = &engine_context.mGameWorld.mEManager.mECSManager;
        const scene_ecs = &engine_context.mGameWorld.mSManager.mECSManager;
        transforms_locked_in_game = entity_ecs.mLockCounts[EManager.ECSManagerT.ComponentInd(TransformComponent)] > 0;
        scenes_locked_in_game = scene_ecs.mLockCounts[SManager.ECSManagerT.ComponentInd(SceneComponent)] > 0;
    }
};

test "a UI system reaches a world's components only while the world is in use" {
    //the warning naming the missing kind is expected; kept off the build runner's output (see TmplTests)
    std.testing.log_level = .err;
    defer std.testing.log_level = .warn;
    const engine = try TestEngine.Init();
    defer engine.Deinit() catch unreachable;
    const engine_context = engine.mEngineContext;
    const ui_ecs = &engine_context.mUIManager.mECSManager;

    try std.testing.expectError(error.NoConnectedECS, engine_context.mSystems.RunSystem(ReadsWorldTransforms, engine_context, ui_ecs, .{}));

    try engine_context.StartUsingWorld(&engine_context.mGameWorld);
    try engine_context.mSystems.RunSystem(ReadsWorldTransforms, engine_context, ui_ecs, .{});
    try std.testing.expect(transforms_locked_in_game);
    //what it didn't list stays as it was
    try std.testing.expect(!scenes_locked_in_game);
    engine_context.StopUsingWorld(&engine_context.mGameWorld);
}
