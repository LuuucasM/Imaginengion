//! The program a game runs on: the project's entries (Project.Entry) played in the game world, with no editor. Started
//! with the project file's path as its first argument (`zig build rungame -- <path>/<name>.imprj`).
//!
//! The frame is the editor's while it plays (EditorProgram.OnUpdate), on mGameWorld and without the editor's own UI
//! and panels. What the game starts as is up to its scripts: the entry scene is loaded and the entry player and game
//! mode are spawned, then the scenes' OnSceneStart scripts run, which set the game up (which entity the player
//! possesses, ...). The first player that possesses something with a viewpoint is drawn to the whole window.
const std = @import("std");

const EngineContext = @import("../Core/EngineContext.zig");
const Project = @import("../Core/Project.zig");
const Tracy = @import("../Core/Tracy.zig");
const WorldManager = @import("../Core/WorldManager.zig");
const ScriptsProcessor = @import("../Scripts/ScriptsProcessor.zig");
const Renderer = @import("../Renderer/Renderer.zig");
const RayCast = @import("../Physics/RayCast.zig");
const PhysicsManager = @import("../Physics/PhysicsManager.zig");
const LayoutSystem = @import("../UI/LayoutSystem.zig");
const UIManager = @import("../UI/UIManager.zig");
const PointerSystem = @import("../Pointer/PointerSystem.zig");
const EventResult = @import("../Events/EventManager.zig").EventResult;

const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const Player = @import("../ECSObjects/Player.zig");
const GameContext = @import("../ECSObjects/GameContext.zig");

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const OnKeyPressedScript = EntityComponents.OnKeyPressedScript;
const OnUpdateScript = EntityComponents.OnUpdateScript;
const OnSceneStartScript = @import("../ECSComponents/SComponents.zig").OnSceneStartScript;
const PossessComponent = @import("../ECSComponents/PComponents.zig").PossessComponent;

const WindowEventData = @import("../Events/WindowEventData.zig");
const WindowEvent = WindowEventData.EventT;
const WorldEvent = @import("../Events/WorldEventData.zig").EventT;
const WorldEventData = @import("../Events/WorldEventData.zig");
const UIEvent = @import("../Events/UIEventData.zig").EventT;
const PointerEvent = @import("../Events/PointerEventData.zig").EventT;
const PhysicsEventData = @import("../Events/PhysicsEventData.zig");
const PhysicsEvent = PhysicsEventData.EventT;
const EditorEvent = @import("../Events/EditorEventData.zig").EventT;

const EEventData = @import("../Events/EManagerData.zig");
const GCEventData = @import("../Events/GCManagerData.zig");
const PEventData = @import("../Events/PManagerData.zig");
const SEventData = @import("../Events/SManagerData.zig");
const ECSEventData = @import("../Events/ECSEventData.zig");

const AManager = @import("../ECSManagers/AManager.zig");
const EManager = @import("../ECSManagers/EManager.zig");
const GCManager = @import("../ECSManagers/GCManager.zig");
const PManager = @import("../ECSManagers/PManager.zig");
const SManager = @import("../ECSManagers/SManager.zig");

const AManagerEvent = AManager.EventManagerT.EventType;
const AudioManagerEvent = @import("../AudioManager/AudioManager.zig").EventManagerT.EventType;
const EManagerEvent = EManager.EventManagerT.EventType;
const GCManagerEvent = GCManager.EventManagerT.EventType;
const PManagerEvent = PManager.EventManagerT.EventType;
const SManagerEvent = SManager.EventManagerT.EventType;
const ECSEvent = EManager.ECSManagerT.ECSEventManager.EventType;
const UIECSEvent = UIManager.ECSManagerT.ECSEventManager.EventType;

const GameProgram = @This();

/// Hands the pointer's and the UI's events to entities' event scripts
mEventScripts: ScriptsProcessor.EventScripts = .{},

/// Opens the project named by the first argument and starts its game
pub fn Init(self: *GameProgram, engine_context: *EngineContext, args: std.process.Args) !void {
    const zone = Tracy.ZoneInit("GameProgram::Init", @src());
    defer zone.Deinit();
    _ = self;

    const frame_allocator = engine_context.FrameAllocator();
    const arg_list = try args.toSlice(frame_allocator);
    if (arg_list.len < 2) {
        std.log.err("No project to run: pass its project file, e.g. zig build rungame -- C:/Games/MyGame/MyGame.imprj", .{});
        return error.NoProject;
    }
    const project_path = if (std.fs.path.isAbsolute(arg_list[1]))
        arg_list[1]
    else
        try std.fs.path.join(frame_allocator, &.{ engine_context.mAssetManager.mCWDPath.items, arg_list[1] });

    try engine_context.mProject.Open(engine_context, project_path);
    engine_context.mUIManager.LoadTheme(engine_context);

    try StartGame(engine_context);
}

pub fn Deinit(_: *GameProgram, _: *EngineContext) void {}

/// Loads the entry scene, spawns the entry player and game mode, and runs the scenes' start scripts. The project is
/// already open
pub fn StartGame(engine_context: *EngineContext) !void {
    const project = &engine_context.mProject;
    var missing = false;
    for (std.enums.values(Project.Entry)) |entry| {
        if (project.GetEntry(entry).len == 0) {
            std.log.err("The project has no entry {s}, set it in the editor under Project > Set Project Entry", .{@tagName(entry)});
            missing = true;
        }
    }
    if (missing) return error.NoProjectEntry;

    _ = try engine_context.mGameWorld.Load(Scene, engine_context, try project.GetAbsPath(engine_context.FrameAllocator(), project.GetEntry(.Scene)));
    _ = try SpawnEntry(Player, engine_context, .Player);
    _ = try SpawnEntry(GameContext, engine_context, .GameContext);

    _ = try ScriptsProcessor.RunScript(Scene, OnSceneStartScript, .Game, engine_context, .{});
}

/// A copy of the project's `entry` file in the game world, the way scripts spawn one (WorldManager.Spawn)
fn SpawnEntry(comptime obj_t: type, engine_context: *EngineContext, entry: Project.Entry) !obj_t {
    var tmpl = try engine_context.mAssetManager.GetAssetHandle(engine_context, .{ .File = .{
        .rel_path = engine_context.mProject.GetEntry(entry),
        .path_type = .Prj,
    } });
    //the copy keeps its own reference
    defer tmpl.ReleaseAsset();
    return try engine_context.mGameWorld.Spawn(obj_t, engine_context, tmpl);
}

pub fn OnUpdate(self: *GameProgram, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("GameProgram::OnUpdate", @src());
    defer zone.Deinit();

    var callback_list: std.DoublyLinkedList = .{};
    const engine_allocator = engine_context.EngineAllocator();
    const game_world = &engine_context.mGameWorld;

    //-------------Inputs Begin------------------
    {
        const input_zone = Tracy.ZoneInit("Inputs Section", @src());
        defer input_zone.Deinit();

        try engine_context.mAppWindow.PollInputEvents(engine_context);

        //where the mouse is and what it is over, before the presses and clicks below that land on it
        try engine_context.mPointerSystem.Update(engine_context, try PointerInput(engine_context));

        var window_event_callback = EngineContext.WindowEventCallback{ .mCtx = self, .mCallbackFn = OnSystemEvent };
        callback_list.append(&window_event_callback.mNode);
        try engine_context.mSystemEventManager.ProcessCategory(.InputEvent, engine_context, callback_list);
        callback_list.first = null;
        callback_list.last = null;

        var pointer_event_callback = EngineContext.PointerEventCallback{ .mCtx = self, .mCallbackFn = OnPointerEvent };
        callback_list.append(&pointer_event_callback.mNode);
        self.mEventScripts.Reset();
        try engine_context.mPointerEventManager.ProcessCategory(.Pointer, engine_context, callback_list);
        engine_context.mPointerEventManager.ClearCategory(engine_allocator, .Pointer, .ClearRetainingCapacity);
        callback_list.first = null;
        callback_list.last = null;

        var ui_event_callback = EngineContext.UIEventCallback{ .mCtx = self, .mCallbackFn = OnUIEvent };
        callback_list.append(&ui_event_callback.mNode);
        self.mEventScripts.Reset();
        try engine_context.mUIManager.ProcessUIEvents(engine_context, callback_list);
        callback_list.first = null;
        callback_list.last = null;
    }
    //---------------Inputs End-------------------

    //-------------Physics Begin-----------------
    {
        const physics_zone = Tracy.ZoneInit("Physics Section", @src());
        defer physics_zone.Deinit();
        try game_world.OnPhysicsUpdate(engine_context);
    }
    //-------------Physics End-------------------

    //-------------Game Logic Begin--------------
    {
        const game_logic_zone = Tracy.ZoneInit("Game Logic Section", @src());
        defer game_logic_zone.Deinit();

        //what the physics step queued, before the update scripts so they see the result
        var physics_event_callback = PhysicsManager.EventManagerT.EventCallback{ .mCtx = self, .mCallbackFn = ScriptsProcessor.OnPhysicsEvent };
        callback_list.append(&physics_event_callback.mNode);
        try game_world.ProcessEvents(PhysicsEventData, .PostPhysics, engine_context, &callback_list);
        callback_list.first = null;
        callback_list.last = null;

        _ = try ScriptsProcessor.RunScript(Entity, OnUpdateScript, .Game, engine_context, .{});
    }
    //-------------Game Logic End----------------

    //-------------Assets update Begin---------------
    {
        const assets_zone = Tracy.ZoneInit("Assets Section", @src());
        defer assets_zone.Deinit();
        try engine_context.mAssetManager.OnUpdate(engine_context);
    }
    //-------------End Assets Update ------------------

    //--------------Layout Update --------------
    {
        const layout_zone = Tracy.ZoneInit("Layout Update Section", @src());
        defer layout_zone.Deinit();
        try engine_context.mUIManager.UpdateBeforeLayout(engine_context);
        try LayoutSystem.UpdateLayouts(game_world, engine_context);
        const ui_worlds = [_]*WorldManager{game_world};
        try engine_context.mUIManager.UpdateAfterLayout(engine_context, &ui_worlds);
    }
    //---------------End Layout Update ------------

    //--------------World Transform Update --------------
    {
        const world_transform_zone = Tracy.ZoneInit("World Transform Update Section", @src());
        defer world_transform_zone.Deinit();
        try PhysicsManager.UpdateWorldTransforms(game_world, engine_context);
    }
    //---------------End World Transform Update ------------

    //---------Render Begin-------------
    {
        const render_zone = Tracy.ZoneInit("Render Section", @src());
        defer render_zone.Deinit();
        if (engine_context.mRenderer.BeginFrame(engine_context)) {
            try RenderGame(engine_context);
            engine_context.mRenderer.EndFrame();
        }
    }
    //--------------Render End-------------------

    //--------------Audio Begin------------------
    {
        const audio_zone = Tracy.ZoneInit("Audio Section", @src());
        defer audio_zone.Deinit();
        try engine_context.mAudioManager.OnUpdate(engine_context);
    }
    //--------------Audio End--------------------

    //-----------------Start End of Frame-----------------
    {
        const end_frame_zone = Tracy.ZoneInit("End Frame Section", @src());
        defer end_frame_zone.Deinit();

        var system_event_callback = EngineContext.WindowEventCallback{ .mCtx = self, .mCallbackFn = OnSystemEvent };
        callback_list.append(&system_event_callback.mNode);
        try engine_context.mSystemEventManager.ProcessCategory(.WindowEvent, engine_context, callback_list);
        callback_list.first = null;
        callback_list.last = null;

        //what the world asked for, before the deletes
        var world_event_callback = EngineContext.WorldEventCallback{ .mCtx = self, .mCallbackFn = OnWorldEvent };
        callback_list.append(&world_event_callback.mNode);
        try game_world.ProcessEvents(WorldEventData, .EndOfFrame, engine_context, &callback_list);
        callback_list.first = null;
        callback_list.last = null;

        //the managers' own events before the ECS's, scenes first since deleting one deletes its entities too
        try game_world.ProcessEvents(SEventData, .EndOfFrame, engine_context, &callback_list);
        try game_world.ProcessEvents(GCEventData, .EndOfFrame, engine_context, &callback_list);
        try game_world.ProcessEvents(PEventData, .EndOfFrame, engine_context, &callback_list);
        try game_world.ProcessEvents(EEventData, .EndOfFrame, engine_context, &callback_list);
        try game_world.ProcessEvents(ECSEventData, .EndOfFrame, engine_context, &callback_list);

        try engine_context.mAssetManager.ProcessDestroyedAssets(engine_context);
        try engine_context.mAudioManager.ProcessDestroyedVoices(engine_context);

        //after the assets: a destroyed object asset deletes its object in here
        try engine_context.mAssetWorld.ProcessEvents(SEventData, .EndOfFrame, engine_context, &callback_list);
        try engine_context.mAssetWorld.ProcessEvents(GCEventData, .EndOfFrame, engine_context, &callback_list);
        try engine_context.mAssetWorld.ProcessEvents(PEventData, .EndOfFrame, engine_context, &callback_list);
        try engine_context.mAssetWorld.ProcessEvents(EEventData, .EndOfFrame, engine_context, &callback_list);
        try engine_context.mAssetWorld.ProcessEvents(ECSEventData, .EndOfFrame, engine_context, &callback_list);

        //after the deletes, so an element whose entity went this frame goes with it
        try engine_context.mUIManager.EndFrame(engine_context);

        engine_context.mSystemEventManager.EventsReset(engine_allocator, .ClearRetainingCapacity);
    }
    //-----------------End End of Frame-------------------
}

/// The single synchronous entry point for every event type in the engine, see EditorProgram.OnEvent
pub fn OnEvent(_: *GameProgram, engine_context: *EngineContext, event: anytype) anyerror!EventResult {
    const T = @TypeOf(event.*);

    if (T == PhysicsEvent) {
        switch (event.*) {
            .StepBegin => |e| try ScriptsProcessor.RunPhysicsUpdateScripts(engine_context, e),
            .PreSolve => |e| try ScriptsProcessor.RunPreSolveScripts(engine_context, e),
            else => {},
        }
        return .Continue;
    } else if (T == WindowEvent or T == WorldEvent or T == EditorEvent or T == UIEvent or T == PointerEvent or
        T == UIECSEvent or T == AManagerEvent or T == AudioManagerEvent or T == EManagerEvent or T == GCManagerEvent or
        T == PManagerEvent or T == SManagerEvent or T == ECSEvent)
    {
        return .Continue;
    } else {
        @compileError("GameProgram.OnEvent has no arm for " ++ @typeName(T));
    }
}

fn OnSystemEvent(_: *anyopaque, engine_context: *EngineContext, event: *const WindowEvent) anyerror!EventResult {
    switch (event.*) {
        .WindowClose => engine_context.mIsRunning = false,
        .KeyboardPressed => |e| try OnKeyboardPressed(engine_context, e),
        .MousePressed => |e| try engine_context.mPointerSystem.OnPressed(engine_context, e._ButtonCode),
        .MouseReleased => |e| try engine_context.mPointerSystem.OnReleased(engine_context, e._ButtonCode),
        .MouseClicked => |e| try engine_context.mPointerSystem.OnClicked(engine_context, e._ButtonCode, e._Clicks),
        else => {},
    }
    //and then the UI, which works from what the pointer system made of it
    try engine_context.mUIManager.OnInputEvent(engine_context, &engine_context.mPointerSystem, event.*);
    return .Continue;
}

/// Scene by scene from the top of the stack. When the UI takes the key it does at its own scene's turn, see
/// EditorProgram.OnKeyboardPressedEvent
fn OnKeyboardPressed(engine_context: *EngineContext, e: WindowEventData.KeyboardPressedEvent) !void {
    const ui_manager = &engine_context.mUIManager;
    if (ui_manager.KeyTakerFor(e._InputCode)) |taker| {
        if (try ScriptsProcessor.RunScriptAbove(Entity, OnKeyPressedScript, .Game, engine_context, taker.StackPos, .{&e}) == .Continue) {
            try ui_manager.OnKeyTaken(engine_context, taker, e);
        }
    } else {
        _ = try ScriptsProcessor.RunScript(Entity, OnKeyPressedScript, .Game, engine_context, .{&e});
    }
}

fn OnPointerEvent(game_program: *anyopaque, engine_context: *EngineContext, event: *const PointerEvent) anyerror!EventResult {
    const self: *GameProgram = @ptrCast(@alignCast(game_program));
    //e.g. a dragged scrollbar scrolls its region
    try engine_context.mUIManager.OnPointerEvent(engine_context, event.*);
    try self.mEventScripts.OnPointerEvent(engine_context, event.*);
    return .Continue;
}

fn OnUIEvent(game_program: *anyopaque, engine_context: *EngineContext, event: *const UIEvent) anyerror!EventResult {
    const self: *GameProgram = @ptrCast(@alignCast(game_program));
    try self.mEventScripts.OnUIEvent(engine_context, event.*);
    return .Continue;
}

/// What the world asked for this frame, see WorldEventData. No else, so a new world event has to be given an arm here
fn OnWorldEvent(_: *anyopaque, engine_context: *EngineContext, event: *const WorldEvent) anyerror!EventResult {
    switch (event.*) {
        .Default => {},
        .QuitGame => engine_context.mIsRunning = false,
    }
    return .Continue;
}

/// The view drawn to the window: the first player possessing something it can see through. Null until a script has
/// a player possess an entity with a viewpoint
fn ShownView(engine_context: *EngineContext) !?Player.RenderView {
    const game_world = &engine_context.mGameWorld;
    const player_ids = try game_world.GetPlayerGroup(engine_context.FrameAllocator(), .{ .Component = PossessComponent });
    for (player_ids.items) |player_id| {
        if (game_world.GetPlayer(player_id).GetRenderView()) |view| return view;
    }
    return null;
}

/// Where the mouse is and what it is over this frame: the shown view fills the window, so a window pixel is one of
/// its pixels
fn PointerInput(engine_context: *EngineContext) !PointerSystem.Input {
    const mouse = engine_context.mInputManager.GetMousePosition();
    var input = PointerSystem.Input{ .Pixel = mouse };
    const view = try ShownView(engine_context) orelse return input;

    const pointer_view = PointerSystem.View{
        .Ray = Renderer.CameraView.PixelRay(view.mTransform, view.mViewpoint, mouse),
        .CameraView = Renderer.CameraView.FromViewpoint(view.mTransform, view.mViewpoint, engine_context.mAppWindow.GetDisplayScale()),
    };
    input.View = pointer_view;
    const overlays = try view.mPlayer.GetOverlayScenes(engine_context.FrameAllocator());
    if (try RayCast.CastRay(engine_context, &engine_context.mGameWorld, pointer_view.Ray, pointer_view.CameraView, .{ .Overlays = overlays.items }, .{})) |hit| {
        input.Target = hit.Entity;
        input.Position = hit.Position;
    }
    return input;
}

/// Draws the shown view at the window's size and puts it in the window
fn RenderGame(engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("GameProgram::RenderGame", @src());
    defer zone.Deinit();
    const view = try ShownView(engine_context) orelse return;

    const width = engine_context.mAppWindow.GetWidth();
    const height = engine_context.mAppWindow.GetHeight();
    //a minimized window has nothing to draw into
    if (width < 1 or height < 1) return;
    view.mViewpoint.SetViewportSize(width, height);
    try view.mRenderTarget.mComputeTexture.Resize(engine_context, width, height);
    if (!view.mRenderTarget.mComputeTexture.IsCreated()) return;

    const overlays = try view.mPlayer.GetOverlayScenes(engine_context.FrameAllocator());
    try engine_context.mRenderer.RenderWorld(
        &engine_context.mGameWorld,
        .{ .Overlays = overlays.items },
        &engine_context.mEngineStats.GameWorldStats.mRenderStats,
        engine_context,
        Renderer.BuildPushConstants(view.mTransform, view.mViewpoint),
        Renderer.CameraView.FromViewpoint(view.mTransform, view.mViewpoint, engine_context.mAppWindow.GetDisplayScale()),
        &view.mRenderTarget.mComputeTexture,
        .OverlayGame,
    );
    engine_context.mRenderer.mPlatform.Present(&view.mRenderTarget.mComputeTexture);
}
