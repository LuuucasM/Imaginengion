const std = @import("std");

const Window = @import("../Windows/Window.zig");
const ScriptsProcessor = @import("../Scripts/ScriptsProcessor.zig");
const Renderer = @import("../Renderer/Renderer.zig");
const PushConstants = @import("../Renderer/RenderPipeline.zig").SDFPushConstants;
const RenderStats = @import("../Core/EngineStats.zig").RenderStats;
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const VertexArray = @import("../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const Player = @import("../ECSObjects/Player.zig");
const GroupQuery = @import("../ECS/ECSManager.zig").GroupQuery;
const AssetHandle = @import("../ECSObjects/AssetHandle.zig");
const PlatformUtils = @import("../PlatformUtils/PlatformUtils.zig");
const GameContext = @import("../ECSObjects/GameContext.zig");

const PhysicsManager = @import("../Physics/PhysicsManager.zig");
const RayCast = @import("../Physics/RayCast.zig");

const Assets = @import("../ECSComponents/AComponents.zig");
const AudioAsset = Assets.AudioAsset;

const MathTypes = @import("../Math/MathTypes.zig");
const Vec3 = MathTypes.Vec3;
const Quat = MathTypes.Quat;
const Vec4 = MathTypes.Vec4;
const Vec2 = MathTypes.Vec2;

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const TransformComponent = EntityComponents.TransformComponent;
const EntityUUIDComponent = EntityComponents.UUIDComponent;
const OnKeyPressedScript = EntityComponents.OnKeyPressedScript;
const OnUpdateScript = EntityComponents.OnUpdateScript;
const PlayerSlotComponent = EntityComponents.PlayerSlotComponent;
const ViewportComponent = EntityComponents.ViewportComponent;
const EntitySceneComponent = EntityComponents.EntitySceneComponent;
const Viewports = @import("../Renderer/Viewports.zig");
const Widgets = @import("../UI/Widgets.zig");
const OverlayCanvas = @import("../Math/OverlayCanvas.zig");
const Layout = @import("../UI/Layout.zig");
const LayoutComponent = EntityComponents.LayoutComponent;
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const ViewpointComponent = EntityComponents.ViewpointComponent;

const WindowEventData = @import("../Events/WindowEventData.zig");
const WindowEvent = WindowEventData.EventT;

const WorldEventData = @import("../Events/WorldEventData.zig");
const WorldEvent = WorldEventData.EventT;
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

/// Shared by every ECS manager: Entity/Player/Scene/GameContext/AssetHandle ids are all u32, so
/// ECSEventData.EventT(u32) is a single memoized type covering all five.
const ECSEvent = EManager.ECSManagerT.ECSEventManager.EventType;

const SceneComponents = @import("../ECSComponents/SComponents.zig");
const SceneComponent = SceneComponents.SceneComponent;
const OverlayLayerTag = SceneComponents.OverlayLayerTag;
const OnSceneStartScript = SceneComponents.OnSceneStartScript;

const PlayerComponents = @import("../ECSComponents/PComponents.zig");
const PossessComponent = PlayerComponents.PossessComponent;
const PlayerRenderComponent = PlayerComponents.RenderTargetComponent;
const PlayerNameComponent = PlayerComponents.NameComponent;
const OverlayComponent = PlayerComponents.OverlayComponent;

const EditorShell = @import("EditorShell.zig");
const EditorMenuBar = @import("EditorMenuBar.zig");
const AssetHandlesPanel = @import("../EditorPanels/AssetHandlesPanel.zig");
const AudioBusesPanel = @import("../EditorPanels/AudioBusesPanel.zig");
const ComponentsPanel = @import("../EditorPanels/ComponentsPanel.zig");
const ContentBrowserPanel = @import("../EditorPanels/ContentBrowserPanel.zig");
const TmplEditPanel = @import("../EditorPanels/TmplEditPanel.zig");
const ScriptsPanel = @import("../EditorPanels/ScriptsPanel.zig");
const StatsPanel = @import("../EditorPanels/StatsPanel.zig");
const PickingDebugPanel = @import("../EditorPanels/PickingDebugPanel.zig");
const UIElementPanel = @import("../EditorPanels/UIElementPanel.zig");
const UIManager = @import("../UI/UIManager.zig");
const UIECSEvent = UIManager.ECSManagerT.ECSEventManager.EventType;
const HierarchyPanel = @import("../EditorPanels/HierarchyPanel.zig").HierarchyPanel;

const WorldManager = @import("../Core/WorldManager.zig");
const LayoutSystem = @import("../UI/LayoutSystem.zig");
const PointerSystem = @import("../Pointer/PointerSystem.zig");
const ScreenRect = @import("../Math/ScreenRect.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const Serializer = @import("../Serializer/Serializer.zig");
const IndexBuffer = @import("../IndexBuffers/IndexBuffer.zig");
const EventResult = @import("../Events/EventManager.zig").EventResult;

const EditorProgram = @This();
const Tracy = @import("../Core/Tracy.zig");

const ComputeOutput = @import("../Renderer/Renderer.zig").ComputeOutput;

pub const SelectedObject = union(enum) {
    entity: Entity,
    scene_layer: Scene,
    player: Player,
    gamecontext: GameContext,
};

pub const ViewportType = enum {
    ViewportPanel,
    PlayPanel,
};

pub const EditorState = enum(u2) {
    Play = 0,
    Stop = 1,
};

//editor panels
/// The Asset Handles window, in the editor UI
mAssetHandlesPanel: AssetHandlesPanel = .{},
/// The Audio Buses window, in the editor UI
mAudioBusesPanel: AudioBusesPanel = .{},
/// The Components tab, in the editor UI
mComponentsPanel: ComponentsPanel = .{},
/// The Content Browser pane, in the editor UI
mContentBrowserPanel: ContentBrowserPanel = .{},
/// One per template open for editing, see OpenTmpl
mTmplEditPanels: std.ArrayList(TmplEditPanel) = .empty,
/// The Scripts tab, in the editor UI
mScriptsPanel: ScriptsPanel = .{},
/// The Stats window, in the editor UI
mStatsPanel: StatsPanel = .{},
/// The Picking Debug window, in the editor UI
mPickingDebugPanel: PickingDebugPanel = .{},
/// The UI Element window, in the editor UI
mUIElementPanel: UIElementPanel = .{},
/// Hands the pointer's and the UI's events to entities' event scripts
mEventScripts: ScriptsProcessor.EventScripts = .{},
/// Whether the play preview is shown under the viewport (the menu bar's Play Preview)
mShowPlayPreview: bool = true,

/// The hierarchy tabs, in the editor UI
mScenePanel: HierarchyPanel(Scene) = .{},
mEntityPanel: HierarchyPanel(Entity) = .{},
mPlayerPanel: HierarchyPanel(Player) = .{},
mGameModePanel: HierarchyPanel(GameContext) = .{},

mSelectedObj: ?SelectedObject = null,

mEditorState: EditorState = .Stop,
//the player whose view the pointer was last over, which a drag keeps following the mouse through once it leaves
mPointerCamera: ?Player = null,
mRunPlayer: ?Player = null,

//editor UI stuff: the editor's own UI, an overlay only the editor UI player sees, drawn to the whole window
mEditorUIScene: Scene = .uninit,
mEditorUIEntity: Entity = .uninit,
mEditorUIPlayer: Player = .uninit,
/// The editor UI's root: the whole window, which everything else in it goes inside
mEditorUIRoot: Entity = .uninit,
/// How the window is split up: the menu bar, the viewport, the panels' panes (see EditorShell.zig)
mShell: EditorShell = .{},
/// The menus along the top, and which item does what (see EditorMenuBar.zig)
mMenuBar: EditorMenuBar = .{},
/// One viewport quad per view the main viewport shows, in mViewportArea, in the order of the views
mViewportQuads: std.ArrayList(Entity) = .empty,
/// The play preview's viewport quads, one per view it shows
mPlayQuads: std.ArrayList(Entity) = .empty,
/// Whether the main viewport is shown (the Window menu's Viewport)
mShowViewport: bool = true,

//Editor viewport stuff
mEditorViewportScene: Scene = .uninit,
mEditorViewportEntity: Entity = .uninit,
mEditorViewportPlayer: Player = .uninit,

//misc stuff
mEditorFont: AssetHandle = .uninit,
mActiveWorld: *WorldManager = undefined,
mActiveWorldType: EngineContext.WorldType = .Game,

pub fn Init(self: *EditorProgram, engine_context: *EngineContext, _: std.process.Args) !void {
    const zone = Tracy.ZoneInit("EditorProgram::Init", @src());
    defer zone.Deinit();
    //EDITOR UI STUFF================================================
    //the theme and its fonts now, rather than in the middle of the first frame
    engine_context.mUIManager.LoadTheme(engine_context);

    //editor UI keeps its pixel size when the window grows instead of scaling up: the editor world's
    //overlays all measure the screen in pixels
    engine_context.mEditorWorld.mOverlayScaleMode = .ConstantPixelSize;
    self.mEditorUIScene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    self.mEditorUIEntity = try self.mEditorUIScene.CreateEntity(engine_context, Entity.DefaultConfig);
    self.mEditorUIPlayer = try engine_context.mEditorWorld.CreatePlayer(engine_context, .{
        .bAddNameComponent = true,
        .bAddUUIDComponent = true,
        .bAddRenderComponent = true,
        .bAddPossessComponent = true,
        .bAddMicComponent = false,
    });
    try self.mEditorUIEntity.SetTranslation(engine_context, Vec3(f32){ .x = 0.0, .y = 0.0, .z = 15.0 });
    try self.mEditorUIPlayer.GetComponent(PlayerRenderComponent).?.SetViewportSize(engine_context, engine_context.mAppWindow.GetWidth(), engine_context.mAppWindow.GetHeight());
    _ = try self.mEditorUIEntity.AddComponent(engine_context, PlayerSlotComponent{});
    _ = try self.mEditorUIEntity.AddComponent(engine_context, ViewpointComponent{});
    self.mEditorUIPlayer.Possess(self.mEditorUIEntity);
    //the editor's own UI is an overlay only the editor UI player sees
    _ = try self.mEditorUIPlayer.AddComponent(engine_context, OverlayComponent{ .mScene = self.mEditorUIScene });
    try self.mEditorUIScene.SetName(engine_context, "Editor UI");
    try self.mEditorUIEntity.SetName(engine_context, "Editor UI Camera");
    try self.mEditorUIPlayer.SetName(engine_context, "Editor UI Player");
    //the whole window, in the window's background color
    self.mEditorUIRoot = try self.mEditorUIScene.CreateEntity(engine_context, Entity.DefaultConfig);
    try self.mEditorUIRoot.SetName(engine_context, "Editor UI Root");
    try Widgets.AddQuad(engine_context, self.mEditorUIRoot, .{}, .{});
    _ = try self.mEditorUIRoot.AddComponent(engine_context, LayoutComponent{ .mDirection = .Column });
    _ = try self.mEditorUIRoot.AddComponent(engine_context, LayoutItemComponent{
        .mWidth = .{ .Percent = 1 },
        .mHeight = .{ .Percent = 1 },
        .mPlacement = .{ .Anchored = .{} },
    });
    try UIManager.Style(engine_context, self.mEditorUIRoot, "Window");
    //the shell: the menu bar's space, the viewport, the panels' panes
    self.mShell = try EditorShell.Build(engine_context, self.mEditorUIRoot, .{});
    self.mMenuBar = try EditorMenuBar.Build(engine_context, self.mShell.mMenuBar, .{});
    self.mStatsPanel = try StatsPanel.Build(engine_context, self.mEditorUIScene, .{});
    self.mAssetHandlesPanel = try AssetHandlesPanel.Build(engine_context, self.mEditorUIScene, .{});
    self.mAudioBusesPanel = try AudioBusesPanel.Build(engine_context, self.mEditorUIScene, .{});
    self.mUIElementPanel = try UIElementPanel.Build(engine_context, self.mEditorUIScene, .{});
    self.mPickingDebugPanel = try PickingDebugPanel.Build(engine_context, self.mEditorUIScene, .{});
    self.mScriptsPanel = try ScriptsPanel.Build(engine_context, self.mShell.mScriptsPage, .{});
    self.mComponentsPanel = try ComponentsPanel.Build(engine_context, self.mShell.mComponentsPage, .{});
    self.mScenePanel = try HierarchyPanel(Scene).Build(engine_context, self.mShell.mScenesPage, .{});
    self.mEntityPanel = try HierarchyPanel(Entity).Build(engine_context, self.mShell.mEntitiesPage, .{});
    self.mPlayerPanel = try HierarchyPanel(Player).Build(engine_context, self.mShell.mPlayersPage, .{});
    self.mGameModePanel = try HierarchyPanel(GameContext).Build(engine_context, self.mShell.mGameModesPage, .{});
    self.mContentBrowserPanel = try ContentBrowserPanel.Build(engine_context, self.mShell.mContentBrowserPane, try ContentBrowserPanel.Icons.Load(engine_context), .{});
    //=================================================================

    //EDITOR VIEWPORT STUFF==================================================
    self.mEditorViewportScene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    self.mEditorViewportEntity = try self.mEditorViewportScene.CreateEntity(engine_context, Entity.DefaultConfig);
    self.mEditorViewportPlayer = try engine_context.mEditorWorld.CreatePlayer(engine_context, .{
        .bAddNameComponent = true,
        .bAddUUIDComponent = true,
        .bAddRenderComponent = true,
        .bAddPossessComponent = true,
        .bAddMicComponent = false,
    });
    try self.mEditorViewportEntity.SetTranslation(engine_context, Vec3(f32){ .x = 0.0, .y = 0.0, .z = 15.0 });
    try self.mEditorViewportEntity.AddComponentScript(engine_context, "src/Imaginengion/EngineAssets/scripts/EditorCameraInput.zig", .Eng);
    try self.mEditorViewportPlayer.GetComponent(PlayerRenderComponent).?.SetViewportSize(engine_context, engine_context.mAppWindow.GetWidth(), engine_context.mAppWindow.GetHeight());
    _ = try self.mEditorViewportEntity.AddComponent(engine_context, PlayerSlotComponent{});
    _ = try self.mEditorViewportEntity.AddComponent(engine_context, ViewpointComponent{});
    self.mEditorViewportPlayer.Possess(self.mEditorViewportEntity);
    //================================================================================

    self.mActiveWorld = &engine_context.mGameWorld;
    self.mActiveWorldType = .Game;
}

pub fn Deinit(self: *EditorProgram, engine_context: *EngineContext) void {
    const zone = Tracy.ZoneInit("EditorProgram::Deinit", @src());
    defer zone.Deinit();
    //open template windows save on the way out, the same as their X does
    for (self.mTmplEditPanels.items) |*panel| {
        panel.Close(engine_context) catch |err| {
            std.log.err("Failed to save a template window while closing the editor: {s}", .{@errorName(err)});
        };
    }
    self.mTmplEditPanels.deinit(engine_context.EngineAllocator());
    self.mContentBrowserPanel.Deinit(engine_context.EngineAllocator());
    self.mPlayQuads.deinit(engine_context.EngineAllocator());
    self.mViewportQuads.deinit(engine_context.EngineAllocator());
    self.mMenuBar.Deinit(engine_context.EngineAllocator());
    self.mAudioBusesPanel.Deinit(engine_context.EngineAllocator());
    self.mUIElementPanel.Deinit(engine_context.EngineAllocator());
    self.mScriptsPanel.Deinit(engine_context.EngineAllocator());
    self.mComponentsPanel.Deinit(engine_context.EngineAllocator());
    self.mScenePanel.Deinit(engine_context.EngineAllocator());
    self.mEntityPanel.Deinit(engine_context.EngineAllocator());
    self.mPlayerPanel.Deinit(engine_context.EngineAllocator());
    self.mGameModePanel.Deinit(engine_context.EngineAllocator());
}

//Note other systems to consider in the on update loop
//that isnt there already:
//particles
//handling the loading and unloading of assets and scene transitions
//debug/profiling
pub fn OnUpdate(self: *EditorProgram, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("EditorProgram::OnUpdate", @src());
    defer zone.Deinit();

    var callback_list: std.DoublyLinkedList = .{};

    const engine_allocator = engine_context.EngineAllocator();

    //--------------Incoming network packets
    {
        const incoming_zone = Tracy.ZoneInit("Incoming Network Section", @src());
        defer incoming_zone.Deinit();
    }
    //==============End Incoming Network packets

    //-------------Inputs Begin------------------
    {
        const input_zone = Tracy.ZoneInit("Inputs Section", @src());
        defer input_zone.Deinit();

        //Human Inputs
        try engine_context.mAppWindow.PollInputEvents(engine_context);

        //where the mouse is and what it is over, before the presses and clicks below that land on it
        try self.UpdatePointer(engine_context);

        var window_event_callback = EngineContext.WindowEventCallback{ .mCtx = self, .mCallbackFn = OnSystemEvent };
        callback_list.append(&window_event_callback.mNode);
        try engine_context.mSystemEventManager.ProcessCategory(.InputEvent, engine_context, callback_list);
        callback_list.first = null;
        callback_list.last = null;

        //what that did to entities: enter, exit, pressed, released, clicked, dragged, dropped. Before game logic, which
        //reacts to it
        var pointer_event_callback = EngineContext.PointerEventCallback{ .mCtx = self, .mCallbackFn = OnPointerEvent };
        callback_list.append(&pointer_event_callback.mNode);
        self.mEventScripts.Reset();
        try engine_context.mPointerEventManager.ProcessCategory(.Pointer, engine_context, callback_list);
        engine_context.mPointerEventManager.ClearCategory(engine_allocator, .Pointer, .ClearRetainingCapacity);
        callback_list.first = null;
        callback_list.last = null;

        //and what the UI did with it: typing, popups
        var ui_event_callback = EngineContext.UIEventCallback{ .mCtx = self, .mCallbackFn = OnUIEvent };
        callback_list.append(&ui_event_callback.mNode);
        self.mEventScripts.Reset();
        try engine_context.mUIManager.ProcessUIEvents(engine_context, callback_list);
        callback_list.first = null;
        callback_list.last = null;

        //AI Inputs
    }
    //---------------Inputs End-------------------

    //-------------Physics Begin-----------------
    {
        const physics_zone = Tracy.ZoneInit("Physics Section", @src());
        defer physics_zone.Deinit();
        if (self.mEditorState == .Play) {
            try engine_context.mSimulateWorld.OnPhysicsUpdate(engine_context);
        }
    }
    //-------------Physics End-------------------

    //-------------Game Logic Begin--------------
    {
        const game_logic_zone = Tracy.ZoneInit("Game Logic Section", @src());
        defer game_logic_zone.Deinit();

        if (self.mEditorState == .Play) {
            //what the physics step queued. processed here and not inside the step, so whatever reacts is free
            //to move or delete what it hit, and before the update scripts so they see the result
            var physics_event_callback = PhysicsManager.EventManagerT.EventCallback{ .mCtx = self, .mCallbackFn = ScriptsProcessor.OnPhysicsEvent };
            callback_list.append(&physics_event_callback.mNode);
            try engine_context.mSimulateWorld.ProcessEvents(PhysicsEventData, .PostPhysics, engine_context, &callback_list);
            callback_list.first = null;
            callback_list.last = null;

            _ = try ScriptsProcessor.RunScript(Entity, OnUpdateScript, .Simulate, engine_context, .{});
        }
        _ = try ScriptsProcessor.RunScript(Entity, OnUpdateScript, .Editor, engine_context, .{});
    }
    //-------------Game Logic End----------------

    //-------------Animation Begin--------------
    {
        const animation_zone = Tracy.ZoneInit("Animation Section", @src());
        defer animation_zone.Deinit();
    }
    //-------------Animation End----------------

    //-------------Assets update Begin---------------
    {
        const assets_zone = Tracy.ZoneInit("Assets Section", @src());
        defer assets_zone.Deinit();
        try engine_context.mAssetManager.OnUpdate(engine_context);
    }
    //-------------End Assets Update ------------------

    //--------------Layout Update --------------
    //before the transforms, which pick up the translations layout sets
    {
        const layout_zone = Tracy.ZoneInit("Layout Update Section", @src());
        defer layout_zone.Deinit();
        //the shell's room for the menu bar and the play preview, and the main viewport's views, which layout places
        try self.UpdateShell(engine_context);
        //how styled UI looks, which can change the size of its text
        try engine_context.mUIManager.UpdateBeforeLayout(engine_context);
        try LayoutSystem.UpdateLayouts(&engine_context.mGameWorld, engine_context);
        try LayoutSystem.UpdateLayouts(&engine_context.mEditorWorld, engine_context);
        try LayoutSystem.UpdateLayouts(&engine_context.mTmplEditWorld, engine_context);
        if (self.mEditorState == .Play) {
            try LayoutSystem.UpdateLayouts(&engine_context.mSimulateWorld, engine_context);
        }
        //popups go against what opened them, scrollbars where their regions are scrolled and the caret where the laid
        //out text puts it
        //the editor's own UI always, and the game's while it is played
        const ui_worlds = [_]*WorldManager{ &engine_context.mEditorWorld, &engine_context.mSimulateWorld };
        try engine_context.mUIManager.UpdateAfterLayout(engine_context, if (self.mEditorState == .Play) &ui_worlds else ui_worlds[0..1]);
    }
    //---------------End Layout Update ------------

    //--------------World Transform Update --------------
    {
        const world_transform_zone = Tracy.ZoneInit("World Transform Update Section", @src());
        defer world_transform_zone.Deinit();
        try PhysicsManager.UpdateWorldTransforms(&engine_context.mGameWorld, engine_context);
        try PhysicsManager.UpdateWorldTransforms(&engine_context.mEditorWorld, engine_context);
        //templates open for editing, so their previews show where things have been moved to
        try PhysicsManager.UpdateWorldTransforms(&engine_context.mTmplEditWorld, engine_context);
        if (self.mEditorState == .Play) {
            try PhysicsManager.UpdateWorldTransforms(&engine_context.mSimulateWorld, engine_context);
        }
    }
    //---------------End World Transform Update ------------

    //---------Render Begin-------------
    {
        const render_zone = Tracy.ZoneInit("Render Section", @src());
        defer render_zone.Deinit();
        if (engine_context.mRenderer.BeginFrame(engine_context)) {
            try self.RenderRenderTargets(engine_context);
            //the editor's own UI fills the window
            try self.RenderEditorUI(engine_context);
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

    //--------------Outgoing Networking Begin-------------
    {
        const networking_zone = Tracy.ZoneInit("Outgoing Network Section", @src());
        defer networking_zone.Deinit();
    }
    //--------------Outgoing Networking End---------------

    //-----------------Start End of Frame-----------------
    {
        const end_frame_zone = Tracy.ZoneInit("End Frame Section", @src());
        defer end_frame_zone.Deinit();

        //Process window events
        var system_event_callback = EngineContext.WindowEventCallback{ .mCtx = self, .mCallbackFn = OnSystemEvent };
        callback_list.append(&system_event_callback.mNode);
        try engine_context.mSystemEventManager.ProcessCategory(.WindowEvent, engine_context, callback_list);
        callback_list.first = null;
        callback_list.last = null;

        //what the panels asked the editor to do, before the deletes: a template made from an object that is going
        var editor_event_callback = EngineContext.EditorEventCallback{ .mCtx = self, .mCallbackFn = OnEditorEvent };
        callback_list.append(&editor_event_callback.mNode);
        try engine_context.mEditorEventManager.ProcessCategory(.EndOfFrame, engine_context, callback_list);
        callback_list.first = null;
        callback_list.last = null;

        //what the worlds asked for, before the deletes: quitting clears the simulate world, deletes queued in it too
        var world_event_callback = EngineContext.WorldEventCallback{ .mCtx = self, .mCallbackFn = OnWorldEvent };
        callback_list.append(&world_event_callback.mNode);
        for ([_]*WorldManager{ &engine_context.mGameWorld, &engine_context.mEditorWorld, &engine_context.mSimulateWorld, &engine_context.mTmplEditWorld }) |world| {
            try world.ProcessEvents(WorldEventData, .EndOfFrame, engine_context, &callback_list);
        }
        callback_list.first = null;
        callback_list.last = null;

        //the managers' own events before the ECS's: an object's Delete is queued on its manager, and handling it
        //queues the ECS destroy. scenes go first since deleting one deletes its entities too
        for ([_]*WorldManager{ &engine_context.mGameWorld, &engine_context.mEditorWorld, &engine_context.mSimulateWorld, &engine_context.mTmplEditWorld }) |world| {
            try world.ProcessEvents(SEventData, .EndOfFrame, engine_context, &callback_list);
            try world.ProcessEvents(GCEventData, .EndOfFrame, engine_context, &callback_list);
            try world.ProcessEvents(PEventData, .EndOfFrame, engine_context, &callback_list);
            try world.ProcessEvents(EEventData, .EndOfFrame, engine_context, &callback_list);
            try world.ProcessEvents(ECSEventData, .EndOfFrame, engine_context, &callback_list);
        }

        try engine_context.mAssetManager.ProcessDestroyedAssets(engine_context);
        try engine_context.mAudioManager.ProcessDestroyedVoices(engine_context);

        //after the assets: a destroyed object asset deletes its object in here
        try engine_context.mAssetWorld.ProcessEvents(SEventData, .EndOfFrame, engine_context, &callback_list);
        try engine_context.mAssetWorld.ProcessEvents(GCEventData, .EndOfFrame, engine_context, &callback_list);
        try engine_context.mAssetWorld.ProcessEvents(PEventData, .EndOfFrame, engine_context, &callback_list);
        try engine_context.mAssetWorld.ProcessEvents(EEventData, .EndOfFrame, engine_context, &callback_list);
        try engine_context.mAssetWorld.ProcessEvents(ECSEventData, .EndOfFrame, engine_context, &callback_list);

        //after every world's deletes, so an element whose entity went this frame goes with it
        try engine_context.mUIManager.EndFrame(engine_context);

        //after the deletes too: the selected object may have gone this frame, however it went (the hierarchy, its
        //parent going, a script, or its world being cleared when play stopped)
        if (self.mSelectedObj) |selected_obj| {
            const alive = switch (selected_obj) {
                inline else => |object| object.IsActive(),
            };
            if (!alive) self.mSelectedObj = null;
        }

        //end of frame resets
        engine_context.mSystemEventManager.EventsReset(engine_allocator, .ClearRetainingCapacity);
        engine_context.mEditorEventManager.EventsReset(engine_allocator, .ClearRetainingCapacity);
    }
    //-----------------End End of Frame-------------------

}

/// The single synchronous entry point for every event type in the engine. Every event manager's
/// mSyncCallback points here, so an emitter anywhere can reach this with
/// `some_event_manager.Dispatch(engine_context, event)` and get the result back.
///
/// `event` is a `*const T` where T is the firing manager's EventT. The branches are resolved at
/// compile time, so each instantiation compiles down to just its own arm with no runtime type
/// check. The trailing @compileError makes a missing arm a build failure rather than a silent
/// drop, so adding an event type forces a decision here.
///
/// Returning .Consume stops the sync chain and tells the emitter the event was handled. Note the
/// deferred path (ProcessCategory) ignores EventResult today, so .Consume only means something
/// when an event arrives through here.
///
/// The event pointer is only valid for the duration of this call: copy, never store it.
pub fn OnEvent(self: *EditorProgram, engine_context: *EngineContext, event: anytype) anyerror!EventResult {
    // discards so the shell compiles before the arms are filled in; drop them as you go
    _ = self;

    const T = @TypeOf(event.*);

    if (T == WindowEvent) {
        return .Continue;
    } else if (T == WorldEvent) {
        return .Continue;
    } else if (T == EditorEvent) {
        return .Continue;
    } else if (T == UIEvent) {
        return .Continue;
    } else if (T == PointerEvent) {
        return .Continue;
    } else if (T == UIECSEvent) {
        return .Continue;
    } else if (T == PhysicsEvent) {
        switch (event.*) {
            .StepBegin => |e| try ScriptsProcessor.RunPhysicsUpdateScripts(engine_context, e),
            .PreSolve => |e| try ScriptsProcessor.RunPreSolveScripts(engine_context, e),
            else => {},
        }
        return .Continue;
    } else if (T == AManagerEvent) {
        return .Continue;
    } else if (T == AudioManagerEvent) {
        return .Continue;
    } else if (T == EManagerEvent) {
        return .Continue;
    } else if (T == GCManagerEvent) {
        return .Continue;
    } else if (T == PManagerEvent) {
        return .Continue;
    } else if (T == SManagerEvent) {
        return .Continue;
    } else if (T == ECSEvent) {
        return .Continue;
    } else {
        @compileError("EditorProgram.OnEvent has no arm for " ++ @typeName(T));
    }
}

pub fn OnSystemEvent(editor_program: *anyopaque, engine_context: *EngineContext, event: *const WindowEvent) anyerror!EventResult {
    const self: *EditorProgram = @ptrCast(@alignCast(editor_program));
    switch (event.*) {
        .WindowClose => _ = self.OnWindowClose(engine_context),
        .KeyboardPressed => |e| _ = try self.OnKeyboardPressedEvent(engine_context, e),
        .MousePressed => |e| try engine_context.mPointerSystem.OnPressed(engine_context, e._ButtonCode),
        .MouseReleased => |e| try engine_context.mPointerSystem.OnReleased(engine_context, e._ButtonCode),
        .MouseClicked => |e| {
            try engine_context.mPointerSystem.OnClicked(engine_context, e._ButtonCode, e._Clicks);
            //a click, not a press: a left drag rotates the editor camera instead
            if (e._ButtonCode == .BUTTON_LEFT) try self.OnViewportClick(engine_context, .{ .x = e._MouseX, .y = e._MouseY });
        },
        else => {},
    }
    //and then the UI, which works from what the pointer system made of it: presses, typing, the wheel
    try engine_context.mUIManager.OnInputEvent(engine_context, &engine_context.mPointerSystem, event.*);
    return .Continue;
}

/// The pointer events of the frame. Scrollbars react to being dragged; game code and widgets will add their listeners
/// to the callback list in OnUpdate. The Picking Debug panel shows the last one, to see them arrive
pub fn OnPointerEvent(editor_program: *anyopaque, engine_context: *EngineContext, event: *const PointerEvent) anyerror!EventResult {
    const zone = Tracy.ZoneInit("EditorProgram::OnPointerEvent", @src());
    defer zone.Deinit();
    const self: *EditorProgram = @ptrCast(@alignCast(editor_program));
    self.mPickingDebugPanel.OnPointerEvent(event.*);
    //e.g. a dragged scrollbar scrolls its region
    try engine_context.mUIManager.OnPointerEvent(engine_context, event.*);
    //a menu bar item or a panel's button picked: one event per entity in the chain, the item's own is the one with its
    //action
    const entity = event.mEntity;
    switch (event.mEvent) {
        .PointerClicked => |click| if (click.mButton == .BUTTON_LEFT) {
            if (self.mMenuBar.ActionOf(entity)) |action| try self.RunMenuAction(engine_context, action);
            if (self.mAudioBusesPanel.ActionOf(entity)) |action| try AudioBusesPanel.Run(engine_context, action);
            if (self.mUIElementPanel.ActionOf(entity)) |action| try self.mUIElementPanel.Run(engine_context, action);
            if (self.mScriptsPanel.ActionOf(entity)) |script| try ScriptsPanel.Run(engine_context, script);
            if (self.mComponentsPanel.ActionOf(entity)) |action| switch (action) {
                .EditUIElement => try self.mUIElementPanel.Open(engine_context),
                else => try self.mComponentsPanel.Run(engine_context, action),
            };
            if (self.mContentBrowserPanel.ActionOf(entity, click.mClicks)) |action| switch (action) {
                .NewScene => try self.RunMenuAction(engine_context, .NewGameScene),
                else => try self.mContentBrowserPanel.Run(engine_context, action),
            };
            if (self.mScenePanel.ActionOf(entity)) |action| try self.mScenePanel.Run(engine_context, action, self.mActiveWorld, &self.mSelectedObj);
            if (self.mEntityPanel.ActionOf(entity)) |action| try self.mEntityPanel.Run(engine_context, action, self.mActiveWorld, &self.mSelectedObj);
            if (self.mPlayerPanel.ActionOf(entity)) |action| try self.mPlayerPanel.Run(engine_context, action, self.mActiveWorld, &self.mSelectedObj);
            if (self.mGameModePanel.ActionOf(entity)) |action| try self.mGameModePanel.Run(engine_context, action, self.mActiveWorld, &self.mSelectedObj);
            for (self.mTmplEditPanels.items) |*panel| try panel.OnLeftClick(engine_context, entity);
        } else if (click.mButton == .BUTTON_RIGHT) {
            for (self.mTmplEditPanels.items) |*panel| try panel.OnRightClick(engine_context, entity);
            //a hierarchy row's menu is one menu for every row: which row it opens on, before its script opens it
            try self.mScenePanel.OnRightClick(engine_context, entity);
            try self.mEntityPanel.OnRightClick(engine_context, entity);
            try self.mPlayerPanel.OnRightClick(engine_context, entity);
            try self.mGameModePanel.OnRightClick(engine_context, entity);
        },
        .PointerDropped => |dropped| {
            try self.mScriptsPanel.OnDrop(engine_context, entity, dropped, self.mSelectedObj);
            self.mComponentsPanel.OnDrop(entity, dropped);
            for (self.mTmplEditPanels.items) |panel| panel.OnDrop(entity, dropped);
            try self.mScenePanel.OnDrop(engine_context, entity, dropped, self.mActiveWorld, &self.mSelectedObj);
            try self.mEntityPanel.OnDrop(engine_context, entity, dropped, self.mActiveWorld, &self.mSelectedObj);
            try self.mPlayerPanel.OnDrop(engine_context, entity, dropped, self.mActiveWorld, &self.mSelectedObj);
            try self.mGameModePanel.OnDrop(engine_context, entity, dropped, self.mActiveWorld, &self.mSelectedObj);
        },
        else => {},
    }
    //and what an entity does when it is clicked, dragged, dropped on: its scripts
    try self.mEventScripts.OnPointerEvent(engine_context, event.*);
    return .Continue;
}

/// The UI events of the frame: typing and popups. The Picking Debug panel shows the last one
pub fn OnUIEvent(editor_program: *anyopaque, engine_context: *EngineContext, event: *const UIEvent) anyerror!EventResult {
    const zone = Tracy.ZoneInit("EditorProgram::OnUIEvent", @src());
    defer zone.Deinit();
    const self: *EditorProgram = @ptrCast(@alignCast(editor_program));
    const entity_event = switch (event.*) {
        .Entity => |e| e,
        else => return .Continue,
    };
    self.mPickingDebugPanel.OnUIEvent(entity_event);
    //a rigid body's type picked
    try self.mComponentsPanel.OnUIEvent(engine_context, entity_event);
    for (self.mTmplEditPanels.items) |panel| try panel.OnUIEvent(engine_context, entity_event);
    try self.mEventScripts.OnUIEvent(engine_context, entity_event);
    return .Continue;
}

/// Tells the pointer system where the mouse is and what it is over, once a frame: the running game in one of its views,
/// or else the editor's own UI. The editor camera's view is for selecting and
/// moving things, not for using them, so there the pointer is over nothing
fn UpdatePointer(self: *EditorProgram, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("EditorProgram::UpdatePointer", @src());
    defer zone.Deinit();
    try engine_context.mPointerSystem.Update(engine_context, try self.PointerInput(engine_context));
}

/// Where the mouse is and what it is over this frame, for UpdatePointer
fn PointerInput(self: *EditorProgram, engine_context: *EngineContext) !PointerSystem.Input {
    const pointer = &engine_context.mPointerSystem;
    const mouse = engine_context.mInputManager.GetMousePosition();
    var input = PointerSystem.Input{ .Pixel = mouse };

    //a drag that started in the editor UI keeps following the mouse there, even over a view of the game
    if (pointer.IsHolding() and self.mPointerCamera != null and self.IsEditorUICamera(self.mPointerCamera.?)) {
        try self.PointAtEditorUI(engine_context, &input);
        return input;
    }

    if (self.mEditorState == .Play) {
        const game_view = if (try self.ViewUnder(engine_context, mouse)) |view| (if (self.IsEditorCamera(view.Camera)) null else view) else null;
        if (game_view) |view| {
            self.mPointerCamera = view.Camera;
            if (self.PointerViewOf(engine_context, view.Camera, view.Pixel)) |pointer_view| {
                input.View = pointer_view;
                if (try self.CastInView(engine_context, view.Camera, view.World, pointer_view)) |hit| {
                    input.Target = hit.Entity;
                    input.Position = hit.Position;
                }
            }
        } else if (pointer.IsHolding()) {
            //the mouse has left the view a button went down in: it is over nothing, but what is held keeps
            //following it through that view, so a slider dragged past the edge of the panel doesn't stall
            if (self.mPointerCamera) |camera| {
                if (self.PixelOffViewOf(engine_context, camera, mouse)) |pixel| input.View = self.PointerViewOf(engine_context, camera, pixel);
            }
        }
        if (game_view != null or pointer.IsHolding()) return input;
    }

    try self.PointAtEditorUI(engine_context, &input);
    return input;
}

/// Points `input` at what the mouse is over in the editor's own UI, which fills the window
fn PointAtEditorUI(self: *EditorProgram, engine_context: *EngineContext, input: *PointerSystem.Input) !void {
    const zone = Tracy.ZoneInit("EditorProgram::PointAtEditorUI", @src());
    defer zone.Deinit();
    const pointer_view = self.EditorUIView(engine_context, input.Pixel) orelse return;
    input.View = pointer_view;
    self.mPointerCamera = self.mEditorUIPlayer;
    if (try self.CastEditorUI(engine_context, pointer_view)) |hit| {
        input.Target = hit.Entity;
        input.Position = hit.Position;
    }
}

/// The ray through a window pixel into the editor's own UI, and the camera it is seen with. The editor UI is drawn at
/// the window's size, so a window pixel is one of its pixels
fn EditorUIView(self: *const EditorProgram, engine_context: *EngineContext, window_pixel: Vec2(f32)) ?PointerSystem.View {
    const render_view = self.mEditorUIPlayer.GetRenderView() orelse return null;
    return .{
        .Ray = Renderer.CameraView.PixelRay(render_view.mTransform, render_view.mViewpoint, window_pixel),
        .CameraView = Renderer.CameraView.FromViewpoint(render_view.mTransform, render_view.mViewpoint, engine_context.mAppWindow.GetDisplayScale()),
    };
}

/// What a ray into the editor's own UI hits
fn CastEditorUI(self: *const EditorProgram, engine_context: *EngineContext, pointer_view: PointerSystem.View) !?RayCast.RayHit {
    const scene_id = [_]Scene.Type{self.mEditorUIScene.mID};
    const view_scenes = Renderer.ViewScenes{ .Game = .None, .Overlays = &scene_id };
    return try RayCast.CastRay(engine_context, &engine_context.mEditorWorld, pointer_view.Ray, pointer_view.CameraView, view_scenes, .{});
}

/// A view of a world on screen, and the pixel of it a window point is at
pub const ViewUnderMouse = struct {
    /// whose viewpoint drew it
    Camera: Player,
    /// whose entities are in it, not necessarily the camera's own world
    World: EngineContext.WorldType,
    /// continuous, in the camera viewpoint's pixels, ready for CameraView.PixelRay
    Pixel: Vec2(f32),
};

/// The view under `window_pixel`: a viewport quad in the editor's UI, with nothing of the editor UI over it. Every view
/// in the editor shows the active world
pub fn ViewUnder(self: *const EditorProgram, engine_context: *EngineContext, window_pixel: Vec2(f32)) !?ViewUnderMouse {
    const zone = Tracy.ZoneInit("EditorProgram::ViewUnder", @src());
    defer zone.Deinit();
    const ui_view = self.EditorUIView(engine_context, window_pixel) orelse return null;
    const hit = try self.CastEditorUI(engine_context, ui_view) orelse return null;
    const viewport = hit.Entity.GetComponent(ViewportComponent) orelse return null;
    //only a view into the world being edited, or the editor camera's: a template preview's camera sees another world
    if (viewport.mPlayer.mManager != self.mActiveWorld and !self.IsEditorCamera(viewport.mPlayer)) return null;
    const pixel = Viewports.ViewPixelOnRay(hit.Entity, ui_view.Ray, ui_view.CameraView, .OnView) orelse return null;
    return .{ .Camera = viewport.mPlayer, .World = self.mActiveWorldType, .Pixel = pixel };
}

/// The pixel of `camera`'s view a window point is at, even off the view's edges: the viewport quad's showing it. Null if
/// it isn't on screen
fn PixelOffViewOf(self: *const EditorProgram, engine_context: *EngineContext, camera: Player, window_pixel: Vec2(f32)) ?Vec2(f32) {
    const quad = self.ViewportQuadOf(engine_context, camera) orelse return null;
    const ui_view = self.EditorUIView(engine_context, window_pixel) orelse return null;
    return Viewports.ViewPixelOnRay(quad, ui_view.Ray, ui_view.CameraView, .Unbounded);
}

/// The viewport quad in the editor's own UI that shows `camera`'s view, null if none does
fn ViewportQuadOf(self: *const EditorProgram, engine_context: *EngineContext, camera: Player) ?Entity {
    const world = &engine_context.mEditorWorld;
    const entity_ids = world.GetEntityGroup(engine_context.FrameAllocator(), .{ .Component = ViewportComponent }) catch return null;
    for (entity_ids.items) |entity_id| {
        const entity = world.GetEntity(entity_id);
        const shows = entity.GetComponent(ViewportComponent).?.mPlayer;
        if (shows.mID == camera.mID and shows.mManager == camera.mManager and entity.GetComponent(EntitySceneComponent).?.mScene.mID == self.mEditorUIScene.mID) return entity;
    }
    return null;
}

fn IsEditorCamera(self: *const EditorProgram, camera: Player) bool {
    return camera.mID == self.mEditorViewportPlayer.mID and camera.mManager == self.mEditorViewportPlayer.mManager;
}

pub fn IsEditorUICamera(self: *const EditorProgram, camera: Player) bool {
    return camera.mID == self.mEditorUIPlayer.mID and camera.mManager == self.mEditorUIPlayer.mManager;
}

/// The ray through a pixel of a camera's view and the camera it was drawn with, the same ones the renderer used
fn PointerViewOf(_: *EditorProgram, engine_context: *EngineContext, camera: Player, pixel: Vec2(f32)) ?PointerSystem.View {
    const render_view = camera.GetRenderView() orelse return null;
    return .{
        .Ray = Renderer.CameraView.PixelRay(render_view.mTransform, render_view.mViewpoint, pixel),
        .CameraView = Renderer.CameraView.FromViewpoint(render_view.mTransform, render_view.mViewpoint, engine_context.mAppWindow.GetDisplayScale()),
    };
}

/// What a camera's ray hits in `world_type`, among the scenes that camera's view shows, so it lands on what was drawn
fn CastInView(self: *EditorProgram, engine_context: *EngineContext, camera: Player, world_type: EngineContext.WorldType, pointer_view: PointerSystem.View) !?RayCast.RayHit {
    const world = switch (world_type) {
        .Game => &engine_context.mGameWorld,
        .Editor => &engine_context.mEditorWorld,
        .Simulate => &engine_context.mSimulateWorld,
    };
    const view_scenes = try self.ViewScenesFor(engine_context.FrameAllocator(), camera, world);
    return try RayCast.CastRay(engine_context, world, pointer_view.Ray, pointer_view.CameraView, view_scenes, .{});
}

/// What is under a pixel of a view
fn CastAtView(self: *EditorProgram, engine_context: *EngineContext, view: ViewUnderMouse) !?RayCast.RayHit {
    const pointer_view = self.PointerViewOf(engine_context, view.Camera, view.Pixel) orelse return null;
    return try self.CastInView(engine_context, view.Camera, view.World, pointer_view);
}

/// Selects what was clicked in a view, a viewport quad: the game object owning the shape under the mouse, or nothing if
/// the click missed everything. A click outside any view is left alone.
fn OnViewportClick(self: *EditorProgram, engine_context: *EngineContext, click_position: Vec2(f32)) !void {
    const view = try self.ViewUnder(engine_context, click_position) orelse return;
    const hit = try self.CastAtView(engine_context, view);
    const selected: ?Entity = if (hit) |h| h.Entity.GetMainObject() else null;

    try engine_context.mEditorEventManager.Insert(engine_context.EngineAllocator(), .EndOfFrame, .{
        .SelectObjectEvent = .{ .mObject = if (selected) |entity| .{ .entity = entity } else null },
    });
}

/// Opens the template in a window of its own, or brings its window forward if it is already open. Takes over the
/// event's reference on the handle
fn OpenTmpl(self: *EditorProgram, engine_context: *EngineContext, tmpl: AssetHandle) !void {
    var handle = tmpl;
    for (self.mTmplEditPanels.items) |panel| {
        if (panel.IsTmpl(handle)) {
            handle.ReleaseAsset();
            try panel.BringForward(engine_context);
            return;
        }
    }

    const panel = TmplEditPanel.Open(engine_context, handle, self.mEditorViewportScene, self.mEditorUIScene, .{}) catch |err| {
        handle.ReleaseAsset();
        return err;
    };
    try self.mTmplEditPanels.append(engine_context.EngineAllocator(), panel);
}

/// Saves and takes away the template windows that were closed, then updates the open ones
fn UpdateTmplEditPanels(self: *EditorProgram, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("EditorProgram::UpdateTmplEditPanels", @src());
    defer zone.Deinit();
    var i: usize = 0;
    while (i < self.mTmplEditPanels.items.len) {
        const panel = &self.mTmplEditPanels.items[i];
        if (panel.IsOpen()) {
            try panel.Update(engine_context);
            i += 1;
            continue;
        }
        panel.Close(engine_context) catch |err| {
            //nothing is lost: the window opens again with the edits still in it
            std.log.err("Failed to save template, so its window stays open: {s}", .{@errorName(err)});
            try panel.BringForward(engine_context);
            i += 1;
            continue;
        };
        _ = self.mTmplEditPanels.orderedRemove(i);
    }
}

/// Saves the object as a template named after it in the content browser's current folder, overwriting a file with that
/// name, and leaves its shell behind (see Core.MakeTmpl)
fn MakeTmpl(self: *EditorProgram, engine_context: *EngineContext, object: anytype) !void {
    const extension = std.mem.span(Serializer.FileExtension(@TypeOf(object)));
    const abs_path = try std.fmt.allocPrint(engine_context.FrameAllocator(), "{s}/{s}{s}", .{ self.mContentBrowserPanel.CurrentPath(), object.GetName(), extension });
    //the content browser shows folders inside the project or the engine's assets
    const path_type = self.mContentBrowserPanel.CurrentPathType();
    const rel_path = engine_context.mAssetManager.GetRelPath(abs_path, path_type);
    try object.MakeTmpl(engine_context, rel_path, path_type);
}

fn OnWindowClose(_: *EditorProgram, engine_context: *EngineContext) bool {
    //a failed save is logged rather than keeping the editor open, which could leave no way to close it
    engine_context.mProject.Save(engine_context) catch |err| {
        std.log.err("Failed to save the project before closing: {}", .{err});
    };
    engine_context.mIsRunning = false;
    return false;
}

/// What the worlds asked for this frame, see WorldEventData. No else, so a new world event has to be given an arm here
pub fn OnWorldEvent(editor_program: *anyopaque, engine_context: *EngineContext, event: *const WorldEvent) anyerror!EventResult {
    const self: *EditorProgram = @ptrCast(@alignCast(editor_program));

    switch (event.*) {
        .Default => {},
        //the game being played quitting stops play. Only from the simulate world while playing: the state change
        //toggles, so stopping when not playing would start it. Clearing the simulate world from inside its own
        //events is fine, its loop sees the list empty and a second quit this frame goes with it
        .QuitGame => |e| if (self.mEditorState == .Play and e.mWorld == &engine_context.mSimulateWorld) {
            try self.OnChangeEditorStateEvent(engine_context);
        },
    }
    return .Continue;
}

/// What the panels asked the editor to do this frame
pub fn OnEditorEvent(editor_program: *anyopaque, engine_context: *EngineContext, event: *const EditorEvent) anyerror!EventResult {
    const zone = Tracy.ZoneInit("EditorProgram::OnEditorEvent", @src());
    defer zone.Deinit();
    const self: *EditorProgram = @ptrCast(@alignCast(editor_program));
    switch (event.*) {
        .SelectObjectEvent => |e| self.mSelectedObj = e.mObject,
        .MakeTmplEvent => |e| switch (e.mObject) {
            inline else => |object| try self.MakeTmpl(engine_context, object),
        },
        .OpenTmplEvent => |e| self.OpenTmpl(engine_context, e.mTmpl) catch |err| {
            //a file that can't be opened as a template shouldn't take the editor down with it
            std.log.err("Failed to open template: {s}", .{@errorName(err)});
        },
        .DefaultEvent => {},
    }
    return .Continue;
}

pub fn OnKeyboardPressedEvent(self: *EditorProgram, engine_context: *EngineContext, e: WindowEventData.KeyboardPressedEvent) !bool {
    const ui_manager = &engine_context.mUIManager;
    //scene by scene from the top of the stack. When the UI takes the key (a text input with the keyboard, the top
    //popup's Escape) it does at its own scene's turn: the scenes above hear it first and can keep it, the scenes below
    //never do. The editor's own UI is over everything in the window, so when it takes a key the game never hears it
    const editor_taker: ?UIManager.KeyTaker = if (ui_manager.KeyTakerFor(e._InputCode)) |taker| (if (taker.World == &engine_context.mEditorWorld) taker else null) else null;
    if (editor_taker != null) {
        if (try ScriptsProcessor.RunScriptAbove(Entity, OnKeyPressedScript, .Editor, engine_context, editor_taker.?.StackPos, .{&e}) == .Continue) {
            try ui_manager.OnKeyTaken(engine_context, editor_taker.?, e);
        }
        return true;
    }

    _ = try ScriptsProcessor.RunScript(Entity, OnKeyPressedScript, .Editor, engine_context, .{&e});
    if (self.mEditorState == .Play) {
        if (ui_manager.KeyTakerFor(e._InputCode)) |taker| {
            if (try ScriptsProcessor.RunScriptAbove(Entity, OnKeyPressedScript, .Simulate, engine_context, taker.StackPos, .{&e}) == .Continue) {
                try ui_manager.OnKeyTaken(engine_context, taker, e);
            }
        } else {
            _ = try ScriptsProcessor.RunScript(Entity, OnKeyPressedScript, .Simulate, engine_context, .{&e});
        }
    }

    if (e._InputCode == .F5) {
        try self.OnChangeEditorStateEvent(engine_context);
    }


    return true;
}

/// Asks for a theme file and makes it the editor's theme, for this session: how the editor looks, not the game (a
/// game's UI names its own theme files, see StyleComponent). A file in the open project is kept by the project's path,
/// anything else by the engine's
fn PickTheme(_: *EditorProgram, engine_context: *EngineContext) !void {
    const abs_path = try PlatformUtils.OpenFile(engine_context.FrameAllocator(), ".imtheme");
    if (abs_path.len == 0) return;

    const asset_manager = &engine_context.mAssetManager;
    const project = &engine_context.mProject;
    const path_type: @import("../ECSManagers/AManager.zig").PathType = if (project.IsOpen() and std.mem.startsWith(u8, abs_path, project.mPath.items)) .Prj else .Eng;
    const rel_path = asset_manager.GetRelPath(abs_path, path_type);
    const theme = try asset_manager.GetAssetHandle(engine_context, .{ .File = .{ .rel_path = rel_path, .path_type = path_type } });
    engine_context.mUIManager.SetTheme(engine_context, theme);
}

pub fn OnChangeEditorStateEvent(self: *EditorProgram, engine_context: *EngineContext) !void {
    //play copies the whole game world and stop frees the simulate one, so this is the play button hitch
    const zone = Tracy.ZoneInit("EditorProgram::OnChangeEditorStateEvent", @src());
    defer zone.Deinit();

    if (self.mEditorState == .Play) {
        self.mEditorState = .Stop;
        self.mActiveWorld = &engine_context.mGameWorld;
        self.mActiveWorldType = .Game;
        //what the pointer was over and holding, what had the keyboard and the open popups are in the world that's
        //about to go
        engine_context.mPointerSystem.Reset();
        engine_context.mUIManager.Reset(engine_context);
        self.mPointerCamera = null;
        engine_context.mSimulateWorld.clearAndFree(engine_context, .All);
    } else {
        //only start when the run player can actually be drawn, otherwise play shows nothing
        if (self.mRunPlayer) |run_player| {
            if (run_player.GetRenderView() != null) {
                try engine_context.mGameWorld.Copy(engine_context, &engine_context.mSimulateWorld);
                self.mActiveWorld = &engine_context.mSimulateWorld;
                self.mActiveWorldType = .Simulate;
                self.mEditorState = .Play;
                //the game starting, the same as in a built game (GameProgram): its scenes' start scripts set it up
                _ = try ScriptsProcessor.RunScript(Scene, OnSceneStartScript, .Simulate, engine_context, .{});
            }
        }
    }
}

fn RenderRenderTargets(self: *EditorProgram, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("EditorProgram::RenderRenderTargets", @src());
    defer zone.Deinit();

    if (!self.mShowPlayPreview) {
        if (self.mEditorState == .Play) {
            try self.RenderWorldTarget(engine_context, .ViewportPanel);
        } else {
            try self.RenderEditorTarget(engine_context);
        }
    } else {
        try self.RenderEditorTarget(engine_context);
        try self.RenderWorldTarget(engine_context, .PlayPanel);
    }
    //the template windows' previews, sized to their panes as the editor UI's camera sees them
    if (self.EditorUIView(engine_context, .{ .x = 0, .y = 0 })) |ui_view| {
        for (self.mTmplEditPanels.items) |*panel| try panel.RenderPreview(engine_context, ui_view.CameraView);
    }
}

/// Puts the editor's state on the menu bar's items: which panels are shown, what can't be done right now, and the
/// players the play preview can follow
fn UpdateMenuBar(self: *EditorProgram, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("EditorProgram::UpdateMenuBar", @src());
    defer zone.Deinit();
    var shown = std.EnumArray(EditorMenuBar.Panel, bool).initFill(false);
    shown.set(.AssetHandles, self.mAssetHandlesPanel.IsOpen());
    shown.set(.AudioBuses, self.mAudioBusesPanel.IsOpen());
    shown.set(.Components, self.mComponentsPanel.IsOpen());
    shown.set(.ContentBrowser, self.mContentBrowserPanel.IsOpen());
    shown.set(.Scripts, self.mScriptsPanel.IsOpen());
    shown.set(.Stats, self.mStatsPanel.IsOpen());
    shown.set(.PickingDebug, self.mPickingDebugPanel.IsOpen());
    shown.set(.UIElement, self.mUIElementPanel.IsOpen());
    shown.set(.Viewport, self.mShowViewport);

    //only the players the preview can actually draw
    var players: std.ArrayList(Player) = .empty;
    const player_group = try engine_context.mGameWorld.GetPlayerGroup(engine_context.FrameAllocator(), .{ .Component = PossessComponent });
    for (player_group.items) |player_id| {
        const player = engine_context.mGameWorld.GetPlayer(player_id);
        if (player.GetRenderView() != null) try players.append(engine_context.FrameAllocator(), player);
    }

    try self.mMenuBar.Update(engine_context, .{
        .Shown = shown,
        .ProjectOpen = engine_context.mProject.IsOpen(),
        .SceneSelected = if (self.mSelectedObj) |selected_object| selected_object == .scene_layer else false,
        .EntitySelected = if (self.mSelectedObj) |selected_object| selected_object == .entity else false,
        //stopping is always allowed, starting needs a run player that can be drawn
        .CanPlayStop = self.mEditorState == .Play or (if (self.mRunPlayer) |run_player| run_player.GetRenderView() != null else false),
        .PlayPreview = self.mShowPlayPreview,
        .VSync = engine_context.mRenderer.mPresentMode == .VSync,
        .Players = players.items,
        .Following = self.mRunPlayer,
    });
}

/// Does what a menu bar item was picked for
fn RunMenuAction(self: *EditorProgram, engine_context: *EngineContext, action: EditorMenuBar.Action) !void {
    const zone = Tracy.ZoneInit("EditorProgram::RunMenuAction", @src());
    defer zone.Deinit();
    const engine_allocator = engine_context.EngineAllocator();
    switch (action) {
        .NewGameScene => _ = try engine_context.mGameWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig),
        .NewOverlayScene => _ = try engine_context.mGameWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig),
        .OpenScene => {
            const abs_path = try PlatformUtils.OpenFile(engine_allocator, ".imsc");
            if (abs_path.len > 0) _ = try engine_context.mGameWorld.Load(Scene, engine_context, abs_path);
        },
        .SaveScene => if (self.mSelectedObj) |selected_object| {
            if (selected_object == .scene_layer) try engine_context.mGameWorld.SaveScene(engine_context, selected_object.scene_layer);
        },
        .SaveSceneAs => if (self.mSelectedObj) |selected_object| {
            if (selected_object == .scene_layer) try engine_context.mGameWorld.SaveSceneAs(engine_context, selected_object.scene_layer);
        },
        .SaveEntity => if (self.mSelectedObj) |selected_object| {
            if (selected_object == .entity) try engine_context.mGameWorld.SaveEntity(engine_context, selected_object.entity);
        },
        .SaveEntityAs => if (self.mSelectedObj) |selected_object| {
            if (selected_object == .entity) try engine_context.mGameWorld.SaveEntityAs(engine_context, selected_object.entity);
        },
        .NewProject => {
            const abs_path = try PlatformUtils.OpenFolder(engine_context.FrameAllocator());
            if (abs_path.len > 0) {
                try engine_context.mProject.New(engine_context, abs_path);
                try self.mContentBrowserPanel.SetRoot(engine_context, engine_context.mProject.GetPath());
            }
        },
        .OpenProject => {
            const abs_path = try PlatformUtils.OpenFile(engine_context.FrameAllocator(), ".imprj");
            if (abs_path.len > 0) {
                try engine_context.mProject.Open(engine_context, abs_path);
                try self.mContentBrowserPanel.SetRoot(engine_context, engine_context.mProject.GetPath());
            }
        },
        .SaveProject => try engine_context.mProject.Save(engine_context),
        .SetProjectEntry => |entry| {
            const extension = entry.FileExtension();
            const abs_path = try PlatformUtils.OpenFile(engine_context.FrameAllocator(), extension);
            if (abs_path.len > 0) {
                engine_context.mProject.SetEntry(engine_context, entry, abs_path) catch |err| switch (err) {
                    error.NotInProject, error.WrongFileKind => return std.log.warn("The project's entry {s} has to be a {s} file inside the project folder, not {s}", .{ @tagName(entry), std.mem.span(extension), abs_path }),
                    else => return err,
                };
                std.log.info("Project entry {s} set to {s}", .{ @tagName(entry), engine_context.mProject.GetEntry(entry) });
            }
        },
        .Exit => try engine_context.mSystemEventManager.Insert(engine_allocator, .WindowEvent, .{
            .WindowClose = .{ ._Window = &engine_context.mAppWindow },
        }),
        .TogglePanel => |panel| switch (panel) {
            .AssetHandles => try self.mAssetHandlesPanel.Toggle(engine_context),
            .AudioBuses => try self.mAudioBusesPanel.Toggle(engine_context),
            .Components => try self.mComponentsPanel.Toggle(engine_context),
            .ContentBrowser => try self.mContentBrowserPanel.Toggle(engine_context),
            .Scripts => try self.mScriptsPanel.Toggle(engine_context),
            .Stats => try self.mStatsPanel.Toggle(engine_context),
            .PickingDebug => try self.mPickingDebugPanel.Toggle(engine_context),
            .UIElement => try self.mUIElementPanel.Toggle(engine_context),
            .Viewport => self.mShowViewport = !self.mShowViewport,
        },
        .PickTheme => try self.PickTheme(engine_context),
        .PlayStop => try self.OnChangeEditorStateEvent(engine_context),
        .TogglePlayPreview => self.mShowPlayPreview = !self.mShowPlayPreview,
        //menu actions run before this pass of the loop renders, so no frame has its window image yet
        .ToggleVSync => _ = engine_context.mRenderer.SetPresentMode(engine_context, if (engine_context.mRenderer.mPresentMode == .VSync) .Off else .VSync),
        .FollowPlayer => |player| {
            const already = if (self.mRunPlayer) |run_player| run_player.mID == player.mID else false;
            self.mRunPlayer = if (already) null else player;
        },
    }
}

/// Before layout, which sizes what it sets: the play preview shown or not, the menu bar's items showing the editor's
/// state, and a viewport quad in the viewport area for each view it shows, placed by the view's area rect: the editor
/// camera, or while playing in it, every player's view
fn UpdateShell(self: *EditorProgram, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("EditorProgram::UpdateShell", @src());
    defer zone.Deinit();
    try self.mShell.ShowPlayPreview(engine_context, self.mShowPlayPreview);
    try self.UpdateMenuBar(engine_context);
    try self.mStatsPanel.Update(engine_context, &engine_context.mEngineStats);
    try self.mAssetHandlesPanel.Update(engine_context);
    try self.mAudioBusesPanel.Update(engine_context);
    try self.mUIElementPanel.Update(engine_context, self.mSelectedObj);
    try self.mScriptsPanel.Update(engine_context, self.mSelectedObj);
    try self.mComponentsPanel.Update(engine_context, self.mSelectedObj);
    //the world being edited: the game's, or its copy while playing
    try self.mScenePanel.Update(engine_context, self.mActiveWorld, self.mSelectedObj);
    try self.mEntityPanel.Update(engine_context, self.mActiveWorld, self.mSelectedObj);
    try self.mPlayerPanel.Update(engine_context, self.mActiveWorld, self.mSelectedObj);
    try self.mGameModePanel.Update(engine_context, self.mActiveWorld, self.mSelectedObj);
    try self.UpdateTmplEditPanels(engine_context);
    try self.mContentBrowserPanel.Update(engine_context);
    //before this frame's views are drawn, so it reads last frame's view rects the way input picking will
    try self.mPickingDebugPanel.Update(engine_context, self);

    //the viewport shows the editor camera, or the game's players while playing with the play preview off. The play
    //preview shows the run player while stopped, and the game's players while playing
    const frame_allocator = engine_context.FrameAllocator();
    var viewport_views: std.ArrayList(PlacedView) = .empty;
    if (self.mEditorState == .Play and !self.mShowPlayPreview) {
        for ((try self.GetViewportViews(frame_allocator, .ViewportPanel)).items) |view| {
            try viewport_views.append(frame_allocator, .{ .Player = view.mPlayer, .Area = view.mViewpoint.mAreaRect });
        }
    } else {
        try viewport_views.append(frame_allocator, .{ .Player = self.mEditorViewportPlayer, .Area = self.mEditorViewportEntity.GetComponent(ViewpointComponent).?.mAreaRect });
    }
    try SyncViewQuads(engine_context, self.mShell.mViewportArea, &self.mViewportQuads, viewport_views.items, self.mShowViewport, "Viewport");

    var play_views: std.ArrayList(PlacedView) = .empty;
    if (self.mShowPlayPreview) {
        for ((try self.GetViewportViews(frame_allocator, .PlayPanel)).items) |view| {
            try play_views.append(frame_allocator, .{ .Player = view.mPlayer, .Area = view.mViewpoint.mAreaRect });
        }
    }
    try SyncViewQuads(engine_context, self.mShell.mPlayArea, &self.mPlayQuads, play_views.items, self.mShowPlayPreview, "Play View");
}

/// A view to show, and the part of its area its viewpoint's area rect asks for (x, y, width, height, 0 to 1)
pub const PlacedView = struct {
    Player: Player,
    Area: Vec4(f32),
};

/// `area` shown or hidden, and a viewport quad in it for each of `views` (made or deleted to match), each the share of
/// the area it was last laid out at that its area rect asks for: split screen views side by side
pub fn SyncViewQuads(engine_context: *EngineContext, area: Entity, quads: *std.ArrayList(Entity), views: []const PlacedView, shown: bool, name: []const u8) !void {
    const area_item = area.GetComponent(LayoutItemComponent).?;
    if (area_item.mCollapsed == shown) {
        area_item.mCollapsed = !shown;
        try area.MarkLayoutDirty(engine_context);
    }
    const area_width = area_item.mComputedSize.x;
    const area_height = area_item.mComputedSize.y;

    while (quads.items.len < views.len) {
        const quad = try area.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
        try quad.SetName(engine_context, name);
        try Widgets.AddQuad(engine_context, quad, .{}, .{});
        _ = try quad.AddComponent(engine_context, ViewportComponent{});
        _ = try quad.AddComponent(engine_context, LayoutItemComponent{});
        try quads.append(engine_context.EngineAllocator(), quad);
    }
    while (quads.items.len > views.len) {
        try quads.pop().?.Delete(engine_context);
    }

    for (views, quads.items) |view, quad| {
        quad.GetComponent(ViewportComponent).?.mPlayer = view.Player;
        try SetLayoutItem(engine_context, quad, .{
            .mWidth = .{ .Fixed = view.Area.z * area_width },
            .mHeight = .{ .Fixed = view.Area.w * area_height },
            .mPlacement = .{ .Anchored = TopLeftAt(view.Area.x * area_width, view.Area.y * area_height) },
        });
    }
}

/// Pinned by its top left corner to its parent's top left corner, `right` and `down` from it
fn TopLeftAt(right: f32, down: f32) Layout.Anchoring {
    return .{ .Anchor = .{ .x = -1, .y = 1 }, .Pivot = .{ .x = -1, .y = 1 }, .Offset = .{ .x = right, .y = -down } };
}

/// Sets an entity's size, placement and whether it is collapsed, and asks for layout only if that changed it
fn SetLayoutItem(engine_context: *EngineContext, entity: Entity, wanted: struct { mWidth: Layout.Sizing, mHeight: Layout.Sizing, mPlacement: Layout.Placement, mCollapsed: bool = false }) !void {
    const item = entity.GetComponent(LayoutItemComponent).?;
    var updated = item.*;
    updated.mWidth = wanted.mWidth;
    updated.mHeight = wanted.mHeight;
    updated.mPlacement = wanted.mPlacement;
    updated.mCollapsed = wanted.mCollapsed;
    if (std.meta.eql(updated, item.*)) return;
    item.* = updated;
    try entity.MarkLayoutDirty(engine_context);
}

/// Draws the editor UI scene at the window's size and puts it in the window
fn RenderEditorUI(self: *EditorProgram, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("EditorProgram::RenderEditorUI", @src());
    defer zone.Deinit();
    const render_component = self.mEditorUIPlayer.GetComponent(PlayerRenderComponent).?;
    const transform_component = self.mEditorUIEntity.GetComponent(TransformComponent).?;
    const viewpoint_component = self.mEditorUIEntity.GetComponent(ViewpointComponent).?;

    const width = engine_context.mAppWindow.GetWidth();
    const height = engine_context.mAppWindow.GetHeight();
    //a minimized window has nothing to draw into
    if (width < 1 or height < 1) return;
    viewpoint_component.SetViewportSize(width, height);
    try render_component.mComputeTexture.Resize(engine_context, width, height);
    if (!render_component.mComputeTexture.IsCreated()) return;

    try engine_context.mRenderer.RenderScene(
        self.mEditorUIScene,
        &engine_context.mEngineStats.EditorWorldStats.mRenderStats,
        engine_context,
        Renderer.BuildPushConstants(transform_component, viewpoint_component),
        Renderer.CameraView.FromViewpoint(transform_component, viewpoint_component, engine_context.mAppWindow.GetDisplayScale()),
        &render_component.mComputeTexture,
        .Overlay,
    );
    engine_context.mRenderer.mPlatform.Present(&render_component.mComputeTexture);
}

fn RenderEditorTarget(self: *EditorProgram, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("EditorProgram::RenderEditorTarget", @src());
    defer zone.Deinit();
    const render_component = self.mEditorViewportPlayer.GetComponent(PlayerRenderComponent).?;
    const transform_component = self.mEditorViewportEntity.GetComponent(TransformComponent).?;
    const viewpoint_component = self.mEditorViewportEntity.GetComponent(ViewpointComponent).?;

    //the size its viewport quad covers
    if (!self.mShowViewport) return;
    const quad = self.ViewportQuadOf(engine_context, self.mEditorViewportPlayer) orelse return;
    const ui_view = self.EditorUIView(engine_context, .{ .x = 0, .y = 0 }) orelse return;
    try Viewports.FitPlayerToQuad(engine_context, quad, ui_view.CameraView);
    if (!render_component.mComputeTexture.IsCreated()) return;
    try engine_context.mRenderer.RenderWorld(
        self.mActiveWorld,
        try self.ViewScenesFor(engine_context.FrameAllocator(), self.mEditorViewportPlayer, self.mActiveWorld),
        self.ActiveRenderStats(engine_context),
        engine_context,
        Renderer.BuildPushConstants(transform_component, viewpoint_component),
        Renderer.CameraView.FromViewpoint(transform_component, viewpoint_component, engine_context.mAppWindow.GetDisplayScale()),
        &render_component.mComputeTexture,
        .OverlayGame,
    );
}

fn RenderWorldTarget(self: *EditorProgram, engine_context: *EngineContext, viewport_type: ViewportType) !void {
    const zone = Tracy.ZoneInit("EditorProgram::RenderWorldTarget", @src());
    defer zone.Deinit();

    const frame_allocator = engine_context.FrameAllocator();

    const views = try self.GetViewportViews(frame_allocator, viewport_type);

    for (views.items) |view| {
        const render_component = view.mRenderTarget;
        const transform_component = view.mTransform;
        const viewpoint_component = view.mViewpoint;

        //each view is the size of the viewport quad showing it, the viewport's or the play preview's
        if (viewport_type == .ViewportPanel and !self.mShowViewport) return;
        const quad = self.ViewportQuadOf(engine_context, view.mPlayer) orelse continue;
        const ui_view = self.EditorUIView(engine_context, .{ .x = 0, .y = 0 }) orelse continue;
        try Viewports.FitPlayerToQuad(engine_context, quad, ui_view.CameraView);
        if (!render_component.mComputeTexture.IsCreated()) continue;
        try engine_context.mRenderer.RenderWorld(
            self.mActiveWorld,
            try self.ViewScenesFor(frame_allocator, view.mPlayer, self.mActiveWorld),
            self.ActiveRenderStats(engine_context),
            engine_context,
            Renderer.BuildPushConstants(transform_component, viewpoint_component),
            Renderer.CameraView.FromViewpoint(transform_component, viewpoint_component, engine_context.mAppWindow.GetDisplayScale()),
            &render_component.mComputeTexture,
            .OverlayGame,
        );
    }
}

/// Where the renderer puts what it drew of the active world, for the stats panel
fn ActiveRenderStats(self: *EditorProgram, engine_context: *EngineContext) *RenderStats {
    return switch (self.mActiveWorldType) {
        .Game => &engine_context.mEngineStats.GameWorldStats.mRenderStats,
        .Editor => &engine_context.mEngineStats.EditorWorldStats.mRenderStats,
        .Simulate => &engine_context.mEngineStats.SimulateWorldStats.mRenderStats,
    };
}

/// Which scenes a view shows: the whole game layer of `world`, and the overlays its camera sees. The editor camera
/// sees every overlay in the world it looks at, so HUDs can be seen and edited; a player sees only its own
/// (Player.GetOverlayScenes). Rendering, click picking and the Picking Debug panel all ask this, so what can be
/// clicked in a view is always what was drawn in it. Only valid for this frame
pub fn ViewScenesFor(self: *const EditorProgram, frame_allocator: std.mem.Allocator, camera: Player, world: *WorldManager) !Renderer.ViewScenes {
    const is_editor_camera = camera.mID == self.mEditorViewportPlayer.mID and camera.mManager == self.mEditorViewportPlayer.mManager;
    const overlay_scenes = if (is_editor_camera)
        try world.GetSceneGroup(frame_allocator, .{ .Component = OverlayLayerTag })
    else
        try camera.GetOverlayScenes(frame_allocator);
    return .{ .Overlays = overlay_scenes.items };
}

/// The player views a world viewport draws, each already checked by Player.GetRenderView so the
/// render loops never have to trust a component is there. RenderWorldTarget and RenderViewportWorlds
/// must agree on this list, since one renders the textures the other displays. While stopped the
/// play panel is a preview of the selected run player only; otherwise it is every drawable player.
fn GetViewportViews(self: *EditorProgram, frame_allocator: std.mem.Allocator, viewport_type: ViewportType) !std.ArrayList(Player.RenderView) {
    var views: std.ArrayList(Player.RenderView) = .empty;

    if (self.mEditorState == .Stop and viewport_type == .PlayPanel) {
        if (self.mRunPlayer) |run_player| {
            if (run_player.GetRenderView()) |view| try views.append(frame_allocator, view);
        }
        return views;
    }

    const world_manager = self.mActiveWorld;
    const player_ids = try world_manager.GetPlayerGroup(frame_allocator, .{ .Component = PossessComponent });
    for (player_ids.items) |player_id| {
        if (world_manager.GetPlayer(player_id).GetRenderView()) |view| try views.append(frame_allocator, view);
    }
    return views;
}

fn FilterPossessedEntities(frame_allocator: std.mem.Allocator, player_slot_entities: *std.ArrayList(Entity.Type), world_manager: *WorldManager) !void {
    var start: usize = 0;
    var end: usize = player_slot_entities.items.len;

    while (start < end) {
        const entity = world_manager.GetEntity(player_slot_entities.items[start]);
        const player_slot_component = entity.GetComponent(PlayerSlotComponent).?;
        if (player_slot_component.mPlayerEntity.IsActive()) {
            const player = player_slot_component.mPlayerEntity;
            if (player.mID != Player.NullObject) {
                start += 1;
            } else {
                player_slot_entities.items[start] = player_slot_entities.items[end - 1];
                end -= 1;
            }
        } else {
            player_slot_entities.items[start] = player_slot_entities.items[end - 1];
            end -= 1;
        }
    }

    player_slot_entities.shrinkAndFree(frame_allocator, end);
}

