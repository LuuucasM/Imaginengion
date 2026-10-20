//! Game events (Scripts/GameEvents.zig): a script's handlers found by their last parameter, events sent in a world
//! (WorldManager.Emit) handed at their phase to every script with a handler, in order, until one handles it, and a
//! stopped script left out. No DLL is built: the scripts are exported in-process (ScriptExport.Exports) and put straight
//! onto an asset, the way ScriptValuesTests does.
//! Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const WorldManager = @import("../../Core/WorldManager.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const GameContext = @import("../../ECSObjects/GameContext.zig");
const AssetHandle = @import("../../ECSObjects/AssetHandle.zig");
const ECSObject = @import("../../ECSObjects/ECSObject.zig");
const Assets = @import("../../ECSComponents/AComponents.zig");
const ScriptAsset = Assets.ScriptAsset;
const GameEventScript = @import("../../ECSComponents/Shared/ScriptTags.zig").GameEventScript;
const ScriptABI = @import("../../Scripts/ScriptABI.zig");
const ScriptExport = @import("../../Scripts/ScriptExport.zig");
const ScriptsProcessor = @import("../../Scripts/ScriptsProcessor.zig");
const GameEvents = @import("../../Scripts/GameEvents.zig");
const ScriptResult = ScriptABI.ScriptResult;

const Scored = struct {
    pub const Phase: GameEvents.GamePhase = .AfterUpdate;
    mPoints: u32 = 0,
    mBy: Entity = .uninit,
};

/// Sent by the game context's handler for Scored, for the same phase
const ScoreChanged = struct {
    pub const Phase: GameEvents.GamePhase = .AfterUpdate;
    mTotal: u32 = 0,
};

const Collided = struct {
    pub const Phase: GameEvents.GamePhase = .AfterPhysics;
};

/// Who handled what, in order: 'G' the game context's Scored, 'E' the entity's Scored, 'C' the entity's ScoreChanged
var gHandled: std.ArrayList(u8) = .empty;

fn Handled(mark: u8) void {
    gHandled.append(std.testing.allocator, mark) catch unreachable;
}

/// Keeps the score, and says so when it changes
const ScoreKeeper = struct {
    //touches no components
    pub const Reads = &.{};
    pub const Writes = &.{};

    mTotal: u32 = 0,

    pub fn OnScored(self: *@This(), engine_context: *EngineContext, owner: GameContext, event: *const Scored) !ScriptResult {
        Handled('G');
        self.mTotal += event.mPoints;
        try owner.GetWorld().Emit(engine_context, ScoreChanged{ .mTotal = self.mTotal });
        return .Continue;
    }
};
const ScoreKeeperExports = ScriptExport.Exports(ScoreKeeper, "ScoreKeeper", &.{});

/// An entity's script hearing both events, handling Scored so nothing after it gets it
const ScoreText = struct {
    //touches no components
    pub const Reads = &.{};
    pub const Writes = &.{};

    mShown: u32 = 0,
    mLastBy: Entity = .uninit,

    pub fn HearScore(self: *@This(), _: *EngineContext, _: Entity, event: *const Scored) ScriptResult {
        Handled('E');
        self.mLastBy = event.mBy;
        return .Handled;
    }
    pub fn ShowTotal(self: *@This(), _: *EngineContext, _: Entity, event: *const ScoreChanged) ScriptResult {
        Handled('C');
        self.mShown = event.mTotal;
        return .Continue;
    }
};
const ScoreTextExports = ScriptExport.Exports(ScoreText, "ScoreText", &.{});

/// A second entity script for Scored: never reached, ScoreText handles it first in its scene
const Late = struct {
    //touches no components
    pub const Reads = &.{};
    pub const Writes = &.{};

    pub fn OnScored(_: *@This(), _: *EngineContext, _: Entity, _: *const Scored) ScriptResult {
        Handled('L');
        return .Continue;
    }
};
const LateExports = ScriptExport.Exports(Late, "Late", &.{});

const TestWorld = struct {
    mEngineContext: *EngineContext,
    mScene: Scene = .uninit,

    fn Init() !*TestWorld {
        const self = try std.heap.page_allocator.create(TestWorld);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        engine_context._Internal.ThreadedIO = std.Io.Threaded.init(engine_context._Internal.EngineGPA.allocator(), .{
            .concurrent_limit = .nothing,
            .async_limit = .nothing,
        });
        try engine_context.mAssetManager.Init(engine_context);
        try engine_context.mGameWorld.Init(engine_context.EngineAllocator());
        self.mScene = try engine_context.mGameWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
        gHandled = .empty;
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        const engine_allocator = engine_context.EngineAllocator();
        gHandled.deinit(std.testing.allocator);
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

    /// A loaded script asset running `info`, as if its DLL had handed it over
    fn ScriptAssetFor(self: *TestWorld, info: *const ScriptABI.ScriptInfo) !AssetHandle {
        const engine_context = self.mEngineContext;
        const asset_manager = &engine_context.mAssetManager;
        const engine_allocator = engine_context.EngineAllocator();
        const asset_id = try asset_manager.mECSManager.CreateEntity(engine_allocator);
        _ = try asset_manager.mECSManager.AddComponentSync(engine_context, asset_id, Assets.AssetMetaData{ .mRefs = 0 });
        var file_meta_data = Assets.FileMetaData{ .mPathType = .Prj };
        _ = try file_meta_data.mRelPath.print(engine_allocator, "scripts/Test.zig", .{});
        _ = try asset_manager.mECSManager.AddComponentSync(engine_context, asset_id, file_meta_data);
        _ = try asset_manager.mECSManager.AddComponentSync(engine_context, asset_id, ScriptAsset{ ._Info = info });
        return .{ .mID = asset_id, .mManager = asset_manager };
    }

    fn AddScript(self: *TestWorld, object: anytype, info: *const ScriptABI.ScriptInfo) !@TypeOf(object) {
        var handle = try self.ScriptAssetFor(info);
        handle.RetainAsset();
        return try ECSObject.Core(@TypeOf(object)).AddScript(object, self.mEngineContext, handle);
    }
};

test "a script's event handlers are found by their last parameter, whatever they are called" {
    const info = &ScoreTextExports.info;
    try std.testing.expectEqual(@as(u32, 2), info.mHandlerCount);
    try std.testing.expect(info.HandlerFor(GameEvents.IdOf(Scored)) != null);
    try std.testing.expect(info.HandlerFor(GameEvents.IdOf(ScoreChanged)) != null);
    try std.testing.expect(info.HandlerFor(GameEvents.IdOf(Collided)) == null);
    try std.testing.expectEqualStrings("Scored", std.mem.span(info.HandlerFor(GameEvents.IdOf(Scored)).?.mName));
    //an event's id is its name, the same wherever it is compiled
    try std.testing.expectEqual(std.hash.Fnv1a_64.hash("Scored"), GameEvents.IdOf(Scored));
}

test "an event goes to every handler in the world at its phase, the game context first, until one handles it" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const game_world = &engine_context.mGameWorld;

    const game_context = try game_world.CreateGameContext(engine_context, GameContext.DefaultConfig);
    const keeper = try world.AddScript(game_context, &ScoreKeeperExports.info);
    try std.testing.expect(keeper.HasComponent(GameEventScript));
    const text_entity = try world.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
    const text = try world.AddScript(text_entity, &ScoreTextExports.info);
    _ = try world.AddScript(text_entity, &LateExports.info);
    const ball = try world.mScene.CreateEntity(engine_context, Entity.DefaultConfig);

    try game_world.Emit(engine_context, Scored{ .mPoints = 3, .mBy = ball });
    try game_world.Emit(engine_context, Collided{});

    //nothing before its phase, and the other phase's event isn't touched
    try std.testing.expectEqualStrings("", gHandled.items);
    try ScriptsProcessor.ProcessGameEvents(engine_context, game_world, .AfterUpdate);

    //Scored: the game context, then the entity's ScoreText, which keeps it from Late. Then ScoreChanged, sent by the
    //game context's handler, in the same pass
    try std.testing.expectEqualStrings("GEC", gHandled.items);
    const text_instance = @import("../../Scripts/ScriptValues.zig").InstanceOf(text.GetComponent(@import("../../ECSComponents/Shared/ScriptComponent.zig")).?).?;
    const text_values: *ScoreText = @ptrCast(@alignCast(text_instance.mData));
    try std.testing.expectEqual(@as(u32, 3), text_values.mShown);
    try std.testing.expectEqual(ball.mID, text_values.mLastBy.mID);

    //the queue is empty after, the other phase's still waiting
    try std.testing.expectEqual(@as(usize, 0), game_world.mGameEventManager.GetQueue(.AfterUpdate).mEntries.items.len);
    try std.testing.expectEqual(@as(usize, 1), game_world.mGameEventManager.GetQueue(.AfterPhysics).mEntries.items.len);
}

test "a stopped script's handlers don't run" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const game_world = &engine_context.mGameWorld;

    const game_context = try game_world.CreateGameContext(engine_context, GameContext.DefaultConfig);
    const keeper = try world.AddScript(game_context, &ScoreKeeperExports.info);
    const handle = keeper.GetComponent(@import("../../ECSComponents/Shared/ScriptComponent.zig")).?.mScriptAssetHandle;
    engine_context.mAssetManager.GetLoadedAsset(ScriptAsset, handle.mID).?.mStopped = true;

    try game_world.Emit(engine_context, Scored{ .mPoints = 1 });
    try ScriptsProcessor.ProcessGameEvents(engine_context, game_world, .AfterUpdate);
    try std.testing.expectEqualStrings("", gHandled.items);
}
