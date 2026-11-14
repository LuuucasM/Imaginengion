//! Game events (Scripts/GameEvents.zig): a script's handlers found by their last parameter, events sent in a world
//! (WorldManager.Emit) handed at their phase to every script with a handler, in order, until one handles it, and a
//! stopped script left out, and events sent right away (WorldManager.Dispatch) handled before the send returns. No DLL is
//! built: the scripts are exported in-process (ScriptExport.Exports) and put straight onto an asset, the way
//! ScriptValuesTests does.
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
    mTotal: u32 = 0,

    pub fn OnScored(self: *ScoreKeeper, engine_context: *EngineContext, owner: GameContext, event: *const Scored) !ScriptResult {
        Handled('G');
        self.mTotal += event.mPoints;
        try owner.GetWorld().Emit(engine_context, ScoreChanged{ .mTotal = self.mTotal });
        return .Continue;
    }
};
const ScoreKeeperExports = ScriptExport.Exports(ScoreKeeper, "ScoreKeeper", &.{});

/// An entity's script hearing both events, handling Scored so nothing after it gets it
const ScoreText = struct {
    mShown: u32 = 0,
    mLastBy: Entity = .uninit,

    pub fn HearScore(self: *ScoreText, _: *EngineContext, _: Entity, event: *const Scored) ScriptResult {
        Handled('E');
        self.mLastBy = event.mBy;
        return .Handled;
    }
    pub fn ShowTotal(self: *ScoreText, _: *EngineContext, _: Entity, event: *const ScoreChanged) ScriptResult {
        Handled('C');
        self.mShown = event.mTotal;
        return .Continue;
    }
};
const ScoreTextExports = ScriptExport.Exports(ScoreText, "ScoreText", &.{});

/// A second entity script for Scored: never reached, ScoreText handles it first in its scene
const Late = struct {
    pub fn OnScored(_: *Late, _: *EngineContext, _: Entity, _: *const Scored) ScriptResult {
        Handled('L');
        return .Continue;
    }
};
const LateExports = ScriptExport.Exports(Late, "Late", &.{});

/// Dispatches ScoreChanged from inside its handler for Scored: 'R' before, 'r' after
const Relay = struct {
    pub fn OnScored(_: *Relay, engine_context: *EngineContext, owner: GameContext, _: *const Scored) !ScriptResult {
        Handled('R');
        _ = try owner.GetWorld().Dispatch(engine_context, ScoreChanged{ .mTotal = 7 });
        Handled('r');
        return .Continue;
    }
};
const RelayExports = ScriptExport.Exports(Relay, "Relay", &.{});

/// Hears Collided, an event with nothing in it
const Bumped = struct {
    pub fn OnCollided(_: *Bumped, _: *EngineContext, _: GameContext, _: *const Collided) ScriptResult {
        Handled('B');
        return .Continue;
    }
};
const BumpedExports = ScriptExport.Exports(Bumped, "Bumped", &.{});

/// Two entity scripts hearing ScoreChanged, to tell apart which heard it first: 'X' and 'Y'
const ListenerX = struct {
    pub fn OnScoreChanged(_: *ListenerX, _: *EngineContext, _: Entity, _: *const ScoreChanged) ScriptResult {
        Handled('X');
        return .Continue;
    }
};
const ListenerXExports = ScriptExport.Exports(ListenerX, "ListenerX", &.{});
const ListenerY = struct {
    pub fn OnScoreChanged(_: *ListenerY, _: *EngineContext, _: Entity, _: *const ScoreChanged) ScriptResult {
        Handled('Y');
        return .Continue;
    }
};
const ListenerYExports = ScriptExport.Exports(ListenerY, "ListenerY", &.{});

/// What the game context scripts below act on, set by each test
var gTarget: Entity = .uninit;
var gScriptToAdd: AssetHandle = undefined;
var gSceneToMove: Scene = .uninit;

/// Hearing Scored, gives gTarget a gScriptToAdd script: 'A'
const Adder = struct {
    pub fn OnScored(_: *Adder, engine_context: *EngineContext, _: GameContext, _: *const Scored) !ScriptResult {
        Handled('A');
        gScriptToAdd.RetainAsset();
        _ = try ECSObject.Core(Entity).AddScript(gTarget, engine_context, gScriptToAdd);
        return .Continue;
    }
};
const AdderExports = ScriptExport.Exports(Adder, "Adder", &.{});

/// Hearing Scored, deletes gTarget: 'D'
const Deleter = struct {
    pub fn OnScored(_: *Deleter, engine_context: *EngineContext, _: GameContext, _: *const Scored) !ScriptResult {
        Handled('D');
        try gTarget.Delete(engine_context);
        return .Continue;
    }
};
const DeleterExports = ScriptExport.Exports(Deleter, "Deleter", &.{});

/// Hearing Scored, moves gSceneToMove to the top of the game layers: 'M'
const Mover = struct {
    pub fn OnScored(_: *Mover, engine_context: *EngineContext, owner: GameContext, _: *const Scored) !ScriptResult {
        Handled('M');
        try owner.GetWorld().MoveScene(engine_context.Scratch(), gSceneToMove, 1);
        return .Continue;
    }
};
const MoverExports = ScriptExport.Exports(Mover, "Mover", &.{});

const TestWorld = struct {
    mEngineContext: *EngineContext,
    mScene: Scene = .uninit,

    fn Init() !*TestWorld {
        const self = try std.heap.page_allocator.create(TestWorld);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        engine_context._Internal.ThreadPool = std.Io.Threaded.init(engine_context._Internal.KeepHeap.allocator(), .{
            .concurrent_limit = .nothing,
            .async_limit = .nothing,
        });
        try engine_context.mAssetManager.Init(engine_context);
        try engine_context.mGameWorld.Init(engine_context);
        self.mScene = try engine_context.mGameWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
        gHandled = .empty;
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        const keep_allocator = engine_context.Keep();
        gHandled.deinit(std.testing.allocator);
        engine_context.mGameWorld.Deinit(engine_context);
        engine_context.mSerializer.Deinit(keep_allocator);

        const asset_manager = &engine_context.mAssetManager;
        asset_manager.mECSManager.Deinit(engine_context);
        asset_manager.mUUIDToWorldID.deinit(keep_allocator);
        asset_manager.mEventManager.Deinit(keep_allocator);
        asset_manager.mCWDPath.deinit(keep_allocator);

        _ = engine_context._Internal.KeepHeap.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    /// A loaded script asset running `info`, as if its DLL had handed it over
    fn ScriptAssetFor(self: *TestWorld, info: *const ScriptABI.ScriptInfo) !AssetHandle {
        const engine_context = self.mEngineContext;
        const asset_manager = &engine_context.mAssetManager;
        const keep_allocator = engine_context.Keep();
        const asset_id = try asset_manager.mECSManager.CreateEntity(keep_allocator);
        _ = try asset_manager.mECSManager.AddComponentSync(engine_context, asset_id, Assets.AssetMetaData{ .mRefs = 0 });
        var file_meta_data = Assets.FileMetaData{ .mPathType = .Prj };
        _ = try file_meta_data.mRelPath.print(keep_allocator, "scripts/Test.zig", .{});
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
    try std.testing.expectEqual(ScriptResult.Continue, try game_world.Dispatch(engine_context, Scored{ .mPoints = 1 }));
    try std.testing.expectEqualStrings("", gHandled.items);
}

test "a dispatched event is handled before the send returns, and says if a handler kept it from the rest" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const game_world = &engine_context.mGameWorld;

    const game_context = try game_world.CreateGameContext(engine_context, GameContext.DefaultConfig);
    _ = try world.AddScript(game_context, &ScoreKeeperExports.info);
    const text_entity = try world.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
    const text = try world.AddScript(text_entity, &ScoreTextExports.info);
    _ = try world.AddScript(text_entity, &LateExports.info);
    const ball = try world.mScene.CreateEntity(engine_context, Entity.DefaultConfig);

    const result = try game_world.Dispatch(engine_context, Scored{ .mPoints = 3, .mBy = ball });

    //the game context, then ScoreText, which keeps it from Late. ScoreChanged was sent with Emit, so it waits
    try std.testing.expectEqual(ScriptResult.Handled, result);
    try std.testing.expectEqualStrings("GE", gHandled.items);
    const text_instance = @import("../../Scripts/ScriptValues.zig").InstanceOf(text.GetComponent(@import("../../ECSComponents/Shared/ScriptComponent.zig")).?).?;
    const text_values: *ScoreText = @ptrCast(@alignCast(text_instance.mData));
    try std.testing.expectEqual(ball.mID, text_values.mLastBy.mID);

    //only what the handler queued is waiting, Scored itself never was
    const queue = game_world.mGameEventManager.GetQueue(.AfterUpdate);
    try std.testing.expectEqual(@as(usize, 1), queue.mEntries.items.len);
    try std.testing.expectEqual(GameEvents.IdOf(ScoreChanged), queue.mEntries.items[0].mId);
}

test "a dispatch from inside a handler finishes before that handler carries on" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const game_world = &engine_context.mGameWorld;

    const game_context = try game_world.CreateGameContext(engine_context, GameContext.DefaultConfig);
    _ = try world.AddScript(game_context, &RelayExports.info);
    const text_entity = try world.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
    const text = try world.AddScript(text_entity, &ScoreTextExports.info);

    try std.testing.expectEqual(ScriptResult.Handled, try game_world.Dispatch(engine_context, Scored{}));

    try std.testing.expectEqualStrings("RCrE", gHandled.items);
    const text_instance = @import("../../Scripts/ScriptValues.zig").InstanceOf(text.GetComponent(@import("../../ECSComponents/Shared/ScriptComponent.zig")).?).?;
    const text_values: *ScoreText = @ptrCast(@alignCast(text_instance.mData));
    try std.testing.expectEqual(@as(u32, 7), text_values.mShown);
}

test "a script given a handler during a pass hears the pass's later events" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const game_world = &engine_context.mGameWorld;

    const game_context = try game_world.CreateGameContext(engine_context, GameContext.DefaultConfig);
    _ = try world.AddScript(game_context, &AdderExports.info);
    gTarget = try world.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
    gScriptToAdd = try world.ScriptAssetFor(&ListenerXExports.info);

    //Scored's handler adds a script that hears ScoreChanged, which is already waiting behind it
    try game_world.Emit(engine_context, Scored{});
    try game_world.Emit(engine_context, ScoreChanged{});
    try ScriptsProcessor.ProcessGameEvents(engine_context, game_world, .AfterUpdate);
    try std.testing.expectEqualStrings("AX", gHandled.items);
}

test "a script deleted during a pass hears none of the pass's later events" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const game_world = &engine_context.mGameWorld;

    const game_context = try game_world.CreateGameContext(engine_context, GameContext.DefaultConfig);
    _ = try world.AddScript(game_context, &DeleterExports.info);
    gTarget = try world.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try world.AddScript(gTarget, &ListenerXExports.info);

    try game_world.Emit(engine_context, ScoreChanged{});
    try game_world.Emit(engine_context, Scored{});
    try game_world.Emit(engine_context, ScoreChanged{});
    try ScriptsProcessor.ProcessGameEvents(engine_context, game_world, .AfterUpdate);
    try std.testing.expectEqualStrings("XD", gHandled.items);
}

test "a scene moved in the stack during a pass changes the order the pass's later events go in" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const game_world = &engine_context.mGameWorld;

    const game_context = try game_world.CreateGameContext(engine_context, GameContext.DefaultConfig);
    _ = try world.AddScript(game_context, &MoverExports.info);
    //the second game scene goes on top of the first
    const top_scene = try game_world.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    _ = try world.AddScript(try world.mScene.CreateEntity(engine_context, Entity.DefaultConfig), &ListenerXExports.info);
    _ = try world.AddScript(try top_scene.CreateEntity(engine_context, Entity.DefaultConfig), &ListenerYExports.info);
    gSceneToMove = world.mScene;

    //Scored's handler moves the bottom scene to the top between the two ScoreChangeds
    try game_world.Emit(engine_context, ScoreChanged{});
    try game_world.Emit(engine_context, Scored{});
    try game_world.Emit(engine_context, ScoreChanged{});
    try ScriptsProcessor.ProcessGameEvents(engine_context, game_world, .AfterUpdate);
    try std.testing.expectEqualStrings("YXMXY", gHandled.items);
}

test "an event with nothing in it dispatches, ignoring its phase" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const game_world = &engine_context.mGameWorld;

    const game_context = try game_world.CreateGameContext(engine_context, GameContext.DefaultConfig);
    _ = try world.AddScript(game_context, &BumpedExports.info);

    try std.testing.expectEqual(ScriptResult.Continue, try game_world.Dispatch(engine_context, Collided{}));
    try std.testing.expectEqualStrings("B", gHandled.items);
    try std.testing.expectEqual(@as(usize, 0), game_world.mGameEventManager.GetQueue(.AfterPhysics).mEntries.items.len);
}
