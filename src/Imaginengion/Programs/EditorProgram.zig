const std = @import("std");

const Window = @import("../Windows/Window.zig");
const ScriptsProcessor = @import("../Scripts/ScriptsProcessor.zig");
const Renderer = @import("../Renderer/Renderer.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../GameObjects/Entity.zig");
const VertexArray = @import("../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const Player = @import("../Players/Player.zig");
const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;
const AssetHandle = @import("../Assets/AssetHandle.zig");
const imgui = @import("../Core/CImports.zig").imgui;
const PlatformUtils = @import("../PlatformUtils/PlatformUtils.zig");
const GameMode = @import("../GameModes/GameMode.zig");

const Assets = @import("../Assets/Assets.zig");
const AudioAsset = Assets.AudioAsset;

const LinAlg = @import("../Math/LinAlg.zig");
const Vec3f32 = LinAlg.Vec3f32;
const Quatf32 = LinAlg.Quatf32;
const Vec4f32 = LinAlg.Vec4f32;

const EntityComponents = @import("../GameObjects/Components.zig");
const TransformComponent = EntityComponents.TransformComponent;
const EntityUUIDComponent = EntityComponents.UUIDComponent;
const OnInputPressedScript = EntityComponents.OnInputPressedScript;
const OnUpdateScript = EntityComponents.OnUpdateScript;
const PlayerSlotComponent = EntityComponents.PlayerSlotComponent;
const ViewpointComponent = EntityComponents.ViewpointComponent;

const WindowEventData = @import("../Events/WindowEventData.zig");
const WindowEvent = WindowEventData.Event;

const GameEventData = @import("../Events/GameEventData.zig");
const GameEvent = GameEventData.Event;

const ImguiEventData = @import("../Events/ImguiEventData.zig");
const ImguiEvent = ImguiEventData.Event;

const SceneComponents = @import("../Scene/SceneComponents.zig");
const SceneComponent = SceneComponents.SceneComponent;
const OnSceneStartScript = SceneComponents.OnSceneStartScript;

const PlayerComponents = @import("../Players/Components.zig");
const PossessComponent = PlayerComponents.PossessComponent;
const PlayerRenderComponent = PlayerComponents.RenderTargetComponent;

const ImGui = @import("../Imgui/Imgui.zig");
const Dockspace = @import("../Imgui/Dockspace.zig");
const AssetHandlePanel = @import("../Imgui/AssethandlePanel.zig");
const ComponentsPanel = @import("../Imgui/ComponentsPanel.zig");
const ContentBrowserPanel = @import("../Imgui/ContentBrowserPanel.zig");
const ScriptsPanel = @import("../Imgui/ScriptsPanel.zig");
const StatsPanel = @import("../Imgui/StatsPanel.zig");
const ViewportPanel = @import("../Imgui/ViewportPanel.zig");
const ECSDisplayPanel = @import("../Imgui/ECSDisplay.zig");
const RunSettings = @import("../Imgui/RunSettings.zig");

const SceneManager = @import("../Scene/SceneManager.zig");
const SceneLayer = @import("../Scene/SceneLayer.zig");
const FrameBuffer = @import("../FrameBuffers/FrameBuffer.zig");
const TextureFormat = @import("../FrameBuffers/InternalFrameBuffer.zig").TextureFormat;
const IndexBuffer = @import("../IndexBuffers/IndexBuffer.zig");
const EditorProgram = @This();
const Tracy = @import("../Core/Tracy.zig");

pub const SelectedObject = union(enum) {
    entity: Entity,
    scene_layer: SceneLayer,
    player: Player,
    gamemode: GameMode,
};

pub const ViewportType = enum {
    ViewportPanel,
    PlayPanel,
};

pub const EditorState = enum(u2) {
    Play = 0,
    Stop = 1,
};

//editor imgui stuff
_AssetHandlePanel: AssetHandlePanel = .{},
_ComponentsPanel: ComponentsPanel = .{},
_ContentBrowserPanel: ContentBrowserPanel = .{},
_ScriptsPanel: ScriptsPanel = .{},
_StatsPanel: StatsPanel = .{},
_ViewportPanel: ViewportPanel = .{},

mScenePanel: ECSDisplayPanel = .{},
mEntityPanel: ECSDisplayPanel = .{},
mPlayerPanel: ECSDisplayPanel = .{},
mGameModePanel: ECSDisplayPanel = .{},

mRunSettings: RunSettings = .{},

mSelectedObj: ?SelectedObject = null,
mEditorState: EditorState = .Stop,

//editor UI stuff
mEditorUIScene: SceneLayer = .{},
mEditorUIEntity: Entity = .{},
mEditorUIPlayer: Player = .{},

//Editor viewport stuff
mEditorViewportScene: SceneLayer = .{},
mEditorViewportEntity: Entity = .{},
mEditorViewportPlayer: Player = .{},

//misc stuff
mEditorFont: AssetHandle = .{},
mActiveWorld: *SceneManager = undefined,
mActiveWorldType: EngineContext.WorldType = .Game,

pub fn Init(self: *EditorProgram, engine_context: *EngineContext) !void {
    ImGui.Init(&engine_context.mAppWindow);
    self._ComponentsPanel.Init();
    try self._ContentBrowserPanel.Init(engine_context);
    self._ViewportPanel.Init(engine_context.mAppWindow.GetWidth(), engine_context.mAppWindow.GetHeight());

    self.mEditorUIScene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, .{});
    self.mEditorUIEntity = try self.mEditorUIScene.CreateEntity(engine_context, .{});
    self.mEditorUIPlayer = try engine_context.mEditorWorld.CreatePlayer(engine_context, .{ .bAddNameComponent = false, .bAddUUIDComponent = false });

    self.mEditorViewportScene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, .{});
    self.mEditorViewportEntity = try self.mEditorViewportScene.CreateEntity(engine_context, .{});
    self.mEditorViewportPlayer = try engine_context.mEditorWorld.CreatePlayer(engine_context, .{ .bAddNameComponent = false, .bAddUUIDComponent = false });

    self.mEditorUIEntity.GetComponent(TransformComponent).?.Translation = Vec3f32{ 0.0, 0.0, 15.0 };
    self.mEditorViewportEntity.GetComponent(TransformComponent).?.Translation = Vec3f32{ 0.0, 0.0, 15.0 };

    try self.mEditorViewportEntity.AddComponentScript(engine_context, "assets/scripts/EditorCameraInput.zig", .Eng);

    self.mEditorUIPlayer.GetComponent(PlayerRenderComponent).?.SetViewportSize(engine_context.mAppWindow.GetWidth(), engine_context.mAppWindow.GetHeight());
    self.mEditorViewportPlayer.GetComponent(PlayerRenderComponent).?.SetViewportSize(self._ViewportPanel.mViewportWidth, self._ViewportPanel.mViewportHeight);

    _ = try self.mEditorViewportEntity.AddComponent(engine_context, PlayerSlotComponent{});
    _ = try self.mEditorViewportEntity.AddComponent(engine_context, ViewpointComponent{});
    self.mEditorViewportPlayer.Possess(self.mEditorViewportEntity);

    _ = try self.mEditorUIEntity.AddComponent(engine_context, PlayerSlotComponent{});
    self.mEditorUIPlayer.Possess(self.mEditorUIEntity);

    self.mActiveWorld = &engine_context.mGameWorld;
    self.mActiveWorldType = .Game;
}

pub fn Deinit(self: *EditorProgram, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("EditorProgram::Deinit", @src());
    defer zone.Deinit();

    self._ContentBrowserPanel.Deinit(engine_context);
}

//Note other systems to consider in the on update loop
//that isnt there already:
//particles
//handling the loading and unloading of assets and scene transitions
//debug/profiling
pub fn OnUpdate(self: *EditorProgram, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("Program OnUpdate", @src());
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
        engine_context.mAppWindow.PollInputEvents();

        var window_event_callback = EngineContext.WindowEventCallback{ .mCtx = self, .mCallbackFn = OnSystemEvent };
        callback_list.append(&window_event_callback.mNode);
        try engine_context.mSystemEventManager.ProcessCategory(.InputEvent, engine_context, callback_list);
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
            try engine_context.mPhysicsManager.OnUpdate(engine_context, .Simulate);
        }
    }
    //-------------Physics End-------------------

    //-------------Game Logic Begin--------------
    {
        const game_logic_zone = Tracy.ZoneInit("Game Logic Section", @src());
        defer game_logic_zone.Deinit();

        if (self.mEditorState == .Play) {
            _ = try ScriptsProcessor.RunEntityScript(OnUpdateScript, .Simulate, engine_context, .{});
        }
        _ = try ScriptsProcessor.RunEntityScript(OnUpdateScript, .Editor, engine_context, .{});
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

    //--------------World Transform Update --------------
    {
        const assets_zone = Tracy.ZoneInit("World Transform Update Section", @src());
        defer assets_zone.Deinit();
        try engine_context.mPhysicsManager.UpdateWorldTransforms(.Game, engine_context);
        try engine_context.mPhysicsManager.UpdateWorldTransforms(.Editor, engine_context);
        if (self.mEditorState == .Play) {
            try engine_context.mPhysicsManager.UpdateWorldTransforms(.Simulate, engine_context);
        }
    }
    //---------------End World Transform Update ------------

    //---------Render Begin-------------
    {
        const render_zone = Tracy.ZoneInit("Render Section", @src());
        defer render_zone.Deinit();
        if (engine_context.mIsMinimized == false) {
            ImGui.Begin();
            Dockspace.Begin();

            try self._ContentBrowserPanel.OnImguiRender(engine_context);
            try self._AssetHandlePanel.OnImguiRender(engine_context);

            const current_world = switch (self.mEditorState) {
                .Play => EngineContext.WorldType.Simulate,
                .Stop => EngineContext.WorldType.Game,
            };

            try self.mEntityPanel.OnImguiRender(engine_context, current_world, .GameObj);
            try self.mScenePanel.OnImguiRender(engine_context, current_world, .Scenes);
            try self.mPlayerPanel.OnImguiRender(engine_context, current_world, .Players);
            try self.mGameModePanel.OnImguiRender(engine_context, current_world, .GameModes);

            try self._ComponentsPanel.OnImguiRender(engine_context, self.mSelectedObj);
            try self._ScriptsPanel.OnImguiRender(engine_context, self.mSelectedObj);

            try self.RenderLenses(engine_context);

            try self._StatsPanel.OnImguiRender(engine_context);

            try self.OnImguiRender(engine_context);

            var imgui_event_callback = EngineContext.ImguiEventCallback{ .mCtx = self, .mCallbackFn = OnImguiEvent };
            callback_list.append(&imgui_event_callback.mNode);
            try engine_context.mImguiEventManager.ProcessCategory(.RenderEnd, engine_context, callback_list);
            callback_list.first = null;
            callback_list.last = null;

            Dockspace.End();
            ImGui.End(&engine_context.mAppWindow);
        }
    }
    //--------------Render End-------------------

    //--------------Audio Begin------------------
    {
        const audio_zone = Tracy.ZoneInit("Audio Section", @src());
        defer audio_zone.Deinit();
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

        //swap buffers
        engine_context.mRenderer.SwapBuffers();

        //Process window events
        var system_event_callback = EngineContext.WindowEventCallback{ .mCtx = self, .mCallbackFn = OnSystemEvent };
        callback_list.append(&system_event_callback.mNode);
        try engine_context.mSystemEventManager.ProcessCategory(.WindowEvent, engine_context, callback_list);
        callback_list.first = null;
        callback_list.last = null;

        //handle deleted objects this frame
        var game_event_callback = EngineContext.GameEventCallback{ .mCtx = self, .mCallbackFn = OnGameEvent };
        callback_list.append(&game_event_callback.mNode);
        try engine_context.mGameEventManager.ProcessCategory(.FrameEnd, engine_context, callback_list);
        callback_list.first = null;
        callback_list.last = null;

        try engine_context.mGameWorld.ProcessRemovedObj(engine_context);
        try engine_context.mEditorWorld.ProcessRemovedObj(engine_context);
        try engine_context.mSimulateWorld.ProcessRemovedObj(engine_context);

        try engine_context.mAssetManager.ProcessDestroyedAssets(engine_context);

        //end of frame resets
        engine_context.mSystemEventManager.EventsReset(engine_allocator, .ClearRetainingCapacity);
        engine_context.mGameEventManager.EventsReset(engine_allocator, .ClearRetainingCapacity);
        engine_context.mImguiEventManager.EventsReset(engine_allocator, .ClearRetainingCapacity);
    }
    //-----------------End End of Frame-------------------

}

pub fn OnSystemEvent(editor_program: *anyopaque, engine_context: *EngineContext, event: WindowEvent) anyerror!bool {
    const self: *EditorProgram = @ptrCast(@alignCast(editor_program));
    switch (event) {
        .WindowClose => _ = self.OnWindowClose(engine_context),
        .WindowResize => |e| _ = try OnWindowResize(engine_context, e._Width, e._Height),
        .InputPressed => |e| _ = try self.OnInputPressedEvent(engine_context, e),
        else => {},
    }
    return true;
}

fn OnWindowClose(_: *EditorProgram, engine_context: *EngineContext) bool {
    engine_context.mIsRunning = false;
    return false;
}

fn OnWindowResize(engine_context: *EngineContext, width: usize, height: usize) !bool {
    engine_context.mAppWindow.OnWindowResize(width, height);
    return true;
}

pub fn OnGameEvent(editor_program: *anyopaque, engine_context: *EngineContext, event: GameEvent) anyerror!bool {
    const self: *EditorProgram = @ptrCast(@alignCast(editor_program));
    _ = self;
    _ = engine_context;
    _ = event;
    return true;
}

pub fn OnImguiEvent(editor_program: *anyopaque, engine_context: *EngineContext, event: ImguiEvent) anyerror!bool {
    const self: *EditorProgram = @ptrCast(@alignCast(editor_program));
    switch (event) {
        .MoveSceneEvent => |e| {
            try engine_context.mGameWorld.MoveScene(engine_context.FrameAllocator(), e.Scene, e.NewPos);
        },
        .SelectSceneEvent => |e| {
            if (e.SelectedScene) |scene_layer| {
                self.mSelectedObj = .{ .scene_layer = scene_layer };
            } else {
                self.mSelectedObj = null;
            }
        },
        .SelectEntityEvent => |e| {
            if (e.SelectedEntity) |entity| {
                self.mSelectedObj = .{ .entity = entity };
            } else {
                self.mSelectedObj = null;
            }
        },
        .ViewportResizeEvent => |e| {
            self._ViewportPanel.mViewportWidth = e.mWidth;
            self._ViewportPanel.mViewportHeight = e.mHeight;
        },
        .PlayPanelResizeEvent => |e| {
            self._ViewportPanel.mPlayWidth = e.mWidth;
            self._ViewportPanel.mPlayHeight = e.mHeight;
        },
        .DeleteEntityEvent => |e| {
            if (self.mSelectedObj) |object| {
                if (object == .entity) {
                    if (object.entity.mEntityID == e.mEntity.mEntityID) {
                        self.mSelectedObj = null;
                    }
                }
            }
        },
        .DeleteSceneEvent => |e| {
            if (self.mSelectedObj) |object| {
                if (object == .scene_layer) {
                    if (object.scene_layer.mSceneID == e.mScene.mSceneID) {
                        self.mSelectedObj = null;
                    }
                }
            }
        },
        else => std.debug.print("This event has not been handled by editor program!\n", .{}),
    }
    return true;
}

pub fn OnInputPressedEvent(self: *EditorProgram, engine_context: *EngineContext, e: WindowEventData.InputPressedEvent) !bool {
    _ = try ScriptsProcessor.RunEntityScript(OnInputPressedScript, .Editor, engine_context, .{&e});

    if (e._InputCode == .F5) {
        try self.OnChangeEditorStateEvent(engine_context);
    }

    if (self.mEditorState == .Play) {
        _ = try ScriptsProcessor.RunEntityScript(OnInputPressedScript, .Simulate, engine_context, .{&e});
    }

    _ = self._ViewportPanel.OnInputPressedEvent(e);

    return true;
}

pub fn OnChangeEditorStateEvent(self: *EditorProgram, engine_context: *EngineContext) !void {
    if (self.mEditorState == .Play) {
        self.mEditorState = .Stop;
        self.mActiveWorld = &engine_context.mGameWorld;
        try engine_context.mSimulateWorld.clearAndFree(engine_context);
    } else {
        if (self.mRunSettings.mRunPlayer) |run_player| {
            if (run_player.GetComponent(PossessComponent)) |poss_comp| {
                if (poss_comp.mPossessedEntity.IsActive()) {
                    try engine_context.mGameWorld.Copy(engine_context, &engine_context.mSimulateWorld);
                    self.mActiveWorld = &engine_context.mSimulateWorld;
                    self.mEditorState = .Play;
                }
            }
        }
    }
}

fn RenderLenses(self: *EditorProgram, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("Render Lenses", @src());
    defer zone.Deinit();

    if (!self._ViewportPanel.mP_OpenPlay) {
        if (self.mEditorState == .Play) {
            try self.RenderPlayerLens(engine_context, .ViewportPanel);
        } else {
            try self.RenderViewportLens(engine_context, .ViewportPanel);
        }
    } else {
        try self.RenderViewportLens(engine_context, .ViewportPanel);
        try self.RenderPlayerLens(engine_context, .PlayPanel);
    }
}

fn RenderViewportLens(self: *EditorProgram, engine_context: *EngineContext, viewport_type: ViewportType) !void {
    const render_component = self.mEditorViewportPlayer.GetComponent(PlayerRenderComponent).?;
    const transform_component = self.mEditorViewportEntity.GetComponent(TransformComponent).?;
    const viewpoint_component = self.mEditorViewportEntity.GetComponent(ViewpointComponent).?;
    const world_rot = transform_component.GetWorldRotation();
    const world_pos = transform_component.GetWorldPosition();

    switch (viewport_type) {
        .ViewportPanel => render_component.mFrameBuffer.Resize(self._ViewportPanel.mViewportWidth, self._ViewportPanel.mViewportHeight),
        .PlayPanel => render_component.mFrameBuffer.Resize(self._ViewportPanel.mPlayWidth, self._ViewportPanel.mPlayHeight),
    }

    try engine_context.mRenderer.OnUpdate(
        self.mActiveWorldType,
        engine_context,
        .{
            .mRotation = [4]f32{ world_rot[0], world_rot[1], world_rot[2], world_rot[3] }, //this is in (w, x, y, z) format
            .mPosition = [3]f32{ world_pos[0], world_pos[1], world_pos[2] }, //this is in (x, y, z) format
            .mPerspectiveFar = viewpoint_component.mPerspectiveFar,
            .mResolutionWidth = @floatFromInt(viewpoint_component.mViewportWidth),
            .mResolutionHeight = @floatFromInt(viewpoint_component.mViewportHeight),
            .mAspectRatio = viewpoint_component.mAspectRatio,
            .mFOV = viewpoint_component.mPerspectiveFOVRad,
        },
        .{
            .FrameBuffer = &render_component.mFrameBuffer,
            .VertexArray = &render_component.mVertexArray,
            .VertexBuffer = &render_component.mVertexBuffer,
        },
        0b1,
    );
    var frame_buffers: std.ArrayList(*FrameBuffer) = .empty;
    var area_rects: std.ArrayList(Vec4f32) = .empty;

    try frame_buffers.append(engine_context.FrameAllocator(), &render_component.mFrameBuffer);
    try area_rects.append(engine_context.FrameAllocator(), viewpoint_component.mAreaRect);

    switch (viewport_type) {
        .ViewportPanel => {
            try self._ViewportPanel.OnImguiRenderViewport(engine_context, frame_buffers, area_rects);
        },
        .PlayPanel => {
            try self._ViewportPanel.OnImguiRenderPlay(engine_context, frame_buffers, area_rects);
        },
    }
}

fn RenderPlayerLens(self: *EditorProgram, engine_context: *EngineContext, viewport_type: ViewportType) !void {
    const zone = Tracy.ZoneInit("Render Bufferss", @src());
    defer zone.Deinit();

    const scene_manager = self.mActiveWorld;

    const frame_allocator = engine_context.FrameAllocator();

    var frame_buffers: std.ArrayList(*FrameBuffer) = .empty;
    var area_rects: std.ArrayList(Vec4f32) = .empty;

    var player_entites = try scene_manager.GetPlayerGroup(frame_allocator, .{ .Component = PossessComponent });
    try FilterPossessedPlayers(frame_allocator, &player_entites, scene_manager);

    for (player_entites.items) |player_id| {
        const player = scene_manager.GetPlayer(player_id);
        const possess_component = player.GetComponent(PossessComponent).?;
        const render_component = player.GetComponent(PlayerRenderComponent).?;
        const transform_component = possess_component.mPossessedEntity.GetComponent(TransformComponent).?;
        const viewpoint_component = possess_component.mPossessedEntity.GetComponent(ViewpointComponent).?;

        const world_rot = transform_component.GetWorldRotation();
        const world_pos = transform_component.GetWorldPosition();

        switch (viewport_type) {
            .ViewportPanel => render_component.mFrameBuffer.Resize(self._ViewportPanel.mViewportWidth, self._ViewportPanel.mViewportHeight),
            .PlayPanel => render_component.mFrameBuffer.Resize(self._ViewportPanel.mPlayWidth, self._ViewportPanel.mPlayHeight),
        }

        try engine_context.mRenderer.OnUpdate(
            self.mActiveWorldType,
            engine_context,
            .{
                .mRotation = [4]f32{ world_rot[0], world_rot[1], world_rot[2], world_rot[3] }, //this is in (w, x, y, z) format
                .mPosition = [3]f32{ world_pos[0], world_pos[1], world_pos[2] }, //this is in (x, y, z) format
                .mPerspectiveFar = viewpoint_component.mPerspectiveFar,
                .mResolutionWidth = @floatFromInt(viewpoint_component.mViewportWidth),
                .mResolutionHeight = @floatFromInt(viewpoint_component.mViewportHeight),
                .mAspectRatio = viewpoint_component.mAspectRatio,
                .mFOV = viewpoint_component.mPerspectiveFOVRad,
            },
            .{
                .FrameBuffer = &render_component.mFrameBuffer,
                .VertexArray = &render_component.mVertexArray,
                .VertexBuffer = &render_component.mVertexBuffer,
            },
            0b1,
        );

        try frame_buffers.append(frame_allocator, &render_component.mFrameBuffer);
        try area_rects.append(frame_allocator, viewpoint_component.mAreaRect);
    }

    switch (viewport_type) {
        .ViewportPanel => {
            try self._ViewportPanel.OnImguiRenderViewport(engine_context, frame_buffers, area_rects);
        },
        .PlayPanel => {
            try self._ViewportPanel.OnImguiRenderPlay(engine_context, frame_buffers, area_rects);
        },
    }
}

fn FilterPossessedPlayers(frame_allocator: std.mem.Allocator, player_entities: *std.ArrayList(Player.Type), scene_manager: *SceneManager) !void {
    var start: usize = 0;
    var end: usize = 0;

    while (start < end) {
        const player = scene_manager.GetPlayer(player_entities.items[start]);
        const possess_component = player.GetComponent(PossessComponent).?;
        if (possess_component.mPossessedEntity.IsActive()) {
            start += 1;
        } else {
            player_entities.items[start] = player_entities.items[end - 1];
            end -= 1;
        }
    }

    player_entities.shrinkAndFree(frame_allocator, end);
}

fn FilterPossessedEntities(frame_allocator: std.mem.Allocator, player_slot_entities: *std.ArrayList(Entity.Type), scene_manager: *SceneManager) !void {
    var start: usize = 0;
    var end: usize = 0;

    while (start < end) {
        const entity = scene_manager.GetEntity(player_slot_entities.items[start]);
        const player_slot_component = entity.GetComponent(PlayerSlotComponent).?;
        if (player_slot_component.mPlayerEntity.IsActive()) {
            const player = player_slot_component.mPlayerEntity;
            if (player.mEntityID != Player.NullPlayer) {
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

pub fn OnImguiRender(self: *EditorProgram, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("Dockspace OIR", @src());
    defer zone.Deinit();

    const engine_allocator = engine_context.EngineAllocator();

    const my_null_ptr: ?*anyopaque = null;
    if (imgui.igBeginMenuBar() == true) {
        defer imgui.igEndMenuBar();
        if (imgui.igBeginMenu("File", true) == true) {
            defer imgui.igEndMenu();
            if (imgui.igBeginMenu("New Scene", true) == true) {
                defer imgui.igEndMenu();
                if (imgui.igMenuItem_Bool("New Game Scene", "", false, true) == true) {
                    _ = try engine_context.mGameWorld.NewScene(engine_context, .GameLayer, .{});
                }
                if (imgui.igMenuItem_Bool("New Overlay Scene", "", false, true) == true) {
                    _ = try engine_context.mGameWorld.NewScene(engine_context, .OverlayLayer, .{});
                }
            }
            if (imgui.igMenuItem_Bool("Open Scene", "", false, true) == true) {
                const abs_path = try PlatformUtils.OpenFile(engine_allocator, ".imsc");
                if (abs_path.len > 0) {
                    _ = try engine_context.mGameWorld.LoadScene(engine_context, abs_path);
                }
            }
            if (imgui.igMenuItem_Bool("Save Scene", "", false, true) == true) {
                if (self.mSelectedObj) |selected_object| {
                    if (selected_object == .scene_layer) {
                        try engine_context.mGameWorld.SaveScene(engine_context, selected_object.scene_layer);
                    }
                }
            }
            if (imgui.igMenuItem_Bool("Save Scene As...", "", false, true) == true) {
                if (self.mSelectedObj) |selected_object| {
                    if (selected_object == .scene_layer) {
                        try engine_context.mGameWorld.SaveSceneAs(engine_context, selected_object.scene_layer);
                    }
                }
            }
            imgui.igSeparator();
            if (imgui.igMenuItem_Bool("Save Entity", "", false, true)) {
                if (self.mSelectedObj) |selected_object| {
                    if (selected_object == .entity) {
                        try engine_context.mGameWorld.SaveEntity(engine_context, selected_object.entity);
                    }
                }
            }
            if (imgui.igMenuItem_Bool("Save Entity As...", "", false, true)) {
                if (self.mSelectedObj) |selected_object| {
                    if (selected_object == .entity) {
                        try engine_context.mGameWorld.SaveEntityAs(engine_context, selected_object.entity);
                    }
                }
            }
            imgui.igSeparator();
            if (imgui.igMenuItem_Bool("New Project", "", false, true) == true) {
                const abs_path = try PlatformUtils.OpenFolder(engine_context.FrameAllocator());
                if (abs_path.len > 0) {
                    try self._ContentBrowserPanel.OnNewProjectEvent(engine_allocator, abs_path);
                    try engine_context.mAssetManager.OnNewProjectEvent(engine_allocator, abs_path);
                }
            }
            if (imgui.igMenuItem_Bool("Open Project", "", false, true) == true) {
                const abs_path = try PlatformUtils.OpenFile(engine_context.EngineAllocator(), ".imprj");
                if (abs_path.len > 0) {
                    try self._ContentBrowserPanel.OnOpenProjectEvent(engine_allocator, abs_path);
                    try engine_context.mAssetManager.OnOpenProjectEvent(engine_allocator, abs_path);
                }
            }
            imgui.igSeparator();
            if (imgui.igMenuItem_Bool("Exit", @ptrCast(@alignCast(my_null_ptr)), false, true) == true) {
                try engine_context.mSystemEventManager.Insert(engine_allocator, .WindowEvent, .{
                    .WindowClose = .{},
                });
            }
        }
        if (imgui.igBeginMenu("Window", true) == true) {
            defer imgui.igEndMenu();
            if (imgui.igMenuItem_Bool("Asset Handles", @ptrCast(@alignCast(my_null_ptr)), self._AssetHandlePanel._P_Open, true) == true) {
                self._AssetHandlePanel._P_Open = !self._AssetHandlePanel._P_Open;
            }
            if (imgui.igMenuItem_Bool("Components", @ptrCast(@alignCast(my_null_ptr)), self._ComponentsPanel._P_Open, true) == true) {
                self._ComponentsPanel._P_Open = !self._ComponentsPanel._P_Open;
            }
            if (imgui.igMenuItem_Bool("Content Browser", @ptrCast(@alignCast(my_null_ptr)), self._ContentBrowserPanel.mIsVisible, true) == true) {
                self._ContentBrowserPanel.mIsVisible = !self._ContentBrowserPanel.mIsVisible;
            }
            if (imgui.igMenuItem_Bool("Scripts", @ptrCast(@alignCast(my_null_ptr)), self._ScriptsPanel._P_Open, true) == true) {
                self._ScriptsPanel._P_Open = !self._ScriptsPanel._P_Open;
            }
            if (imgui.igMenuItem_Bool("Stats", @ptrCast(@alignCast(my_null_ptr)), self._StatsPanel._P_Open, true) == true) {
                self._StatsPanel._P_Open = !self._StatsPanel._P_Open;
            }
            if (imgui.igMenuItem_Bool("Viewport", @ptrCast(@alignCast(my_null_ptr)), self._ViewportPanel.mP_OpenViewport, true) == true) {
                self._ViewportPanel.mP_OpenViewport = !self._ViewportPanel.mP_OpenViewport;
            }
        }
        if (imgui.igBeginMenu("Editor", true) == true) {
            defer imgui.igEndMenu();
            if (imgui.igMenuItem_Bool("Use Preview Panel", @ptrCast(@alignCast(my_null_ptr)), self._ViewportPanel.mP_OpenPlay, true) == true) {
                self._ViewportPanel.mP_OpenPlay = !self._ViewportPanel.mP_OpenPlay;
            }
        }
    }
}
