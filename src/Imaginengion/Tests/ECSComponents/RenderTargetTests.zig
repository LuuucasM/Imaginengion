//! A render target's GPU texture is made by the renderer, the first time the target is fitted to the size it is drawn
//! at, and never by making the component: not by a new player, loading one or copying one. That is what lets a script,
//! which carries its own copy of the engine code it calls and none of SDL, load scenes and make players. No window or
//! renderer here, so anything that did make a texture would crash on the missing GPU device.
//! Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const TextSerializer = @import("../../Serializer/TextSerializer.zig");
const Player = @import("../../ECSObjects/Player.zig");

const PlayerComponents = @import("../../ECSComponents/PComponents.zig");
const RenderTargetComponent = PlayerComponents.RenderTargetComponent;

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
        //play mode's copy of the world
        try engine_context.mSimulateWorld.Init(engine_context.EngineAllocator());
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mSimulateWorld.Deinit(engine_context);
        engine_context.mSerializer.Deinit(engine_context.EngineAllocator());
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

fn NewRenderingPlayer(engine_context: *EngineContext) !Player {
    var config = Player.DefaultConfig;
    config.bAddRenderComponent = true;
    return try engine_context.mEditorWorld.CreatePlayer(engine_context, config);
}

test "a new player's render target has no texture until it is drawn" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const player = try NewRenderingPlayer(engine_context);
    try std.testing.expect(!player.GetComponent(RenderTargetComponent).?.mComputeTexture.IsCreated());
}

test "a loaded render target has no texture until it is drawn" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const player = try NewRenderingPlayer(engine_context);
    const player_path = try world.FilePath("player_one.impl");
    try TextSerializer.SerializeECSObject(engine_context, player, player_path);
    engine_context.mEditorWorld.clearAndFree(engine_context, .All);

    const loaded_player = try engine_context.mEditorWorld.CreatePlayer(engine_context, Player.BlankConfig);
    try TextSerializer.DeserializeECSObj(engine_context, loaded_player, player_path);
    try std.testing.expect(!loaded_player.GetComponent(RenderTargetComponent).?.mComputeTexture.IsCreated());
}

test "a copied world's render targets have no texture until they are drawn" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const player = try NewRenderingPlayer(engine_context);

    //what pressing play does
    try engine_context.mEditorWorld.Copy(engine_context, &engine_context.mSimulateWorld);

    const copied_player = engine_context.mSimulateWorld.GetPlayer(player.mID);
    try std.testing.expect(!copied_player.GetComponent(RenderTargetComponent).?.mComputeTexture.IsCreated());
}
