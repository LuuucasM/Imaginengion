const std = @import("std");

const Window = @import("../Windows/Window.zig");
const ScriptsProcessor = @import("../Scripts/ScriptsProcessor.zig");
const Renderer = @import("../Renderer/Renderer.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../GameObjects/Entity.zig");
const VertexArray = @import("../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const PlayerManager = @import("../Players/PlayerManager.zig");
const Player = @import("../Players/Player.zig");
const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;
const AssetHandle = @import("../Assets/AssetHandle.zig");

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
const GameObjectUtils = @import("../GameObjects/GameObjectUtils.zig");

const SceneComponents = @import("../Scene/SceneComponents.zig");
const SceneComponent = SceneComponents.SceneComponent;
const OnSceneStartScript = SceneComponents.OnSceneStartScript;

const PlayerComponents = @import("../Players/Components.zig");
const PossessComponent = PlayerComponents.PossessComponent;
const PlayerLens = PlayerComponents.LensComponent;

const SystemEvent = @import("../Events/SystemEvent.zig").SystemEvent;
const InputPressedEvent = @import("../Events/SystemEvent.zig").InputPressedEvent;
const WindowResizeEvent = @import("../Events/SystemEvent.zig").WindowResizeEvent;
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const ImguiEventManager = @import("../Events/ImguiEventManager.zig");
const GameEvent = @import("../Events/GameEvent.zig").GameEvent;
const ChangeEditorStateEvent = @import("../Events/ImguiEvent.zig").ChangeEditorStateEvent;

const ImGui = @import("../Imgui/Imgui.zig");
const Dockspace = @import("../Imgui/Dockspace.zig");
const AssetHandlePanel = @import("../Imgui/AssethandlePanel.zig");
const ComponentsPanel = @import("../Imgui/ComponentsPanel.zig");
const ContentBrowserPanel = @import("../Imgui/ContentBrowserPanel.zig");
const CSEditorPanel = @import("../Imgui/CSEditorPanel.zig");
const ScenePanel = @import("../Imgui/ScenePanel.zig");
const ScriptsPanel = @import("../Imgui/ScriptsPanel.zig");
const StatsPanel = @import("../Imgui/StatsPanel.zig");
const ToolbarPanel = @import("../Imgui/ToolbarPanel.zig");
const ViewportPanel = @import("../Imgui/ViewportPanel.zig");
const SceneSpecPanel = @import("../Imgui/SceneSpecsPanel.zig");

const SceneManager = @import("../Scene/SceneManager.zig");
const SceneLayer = @import("../Scene/SceneLayer.zig");
const EditorState = @import("../Imgui/ToolbarPanel.zig").EditorState;
const FrameBuffer = @import("../FrameBuffers/FrameBuffer.zig");
const TextureFormat = @import("../FrameBuffers/InternalFrameBuffer.zig").TextureFormat;
const IndexBuffer = @import("../IndexBuffers/IndexBuffer.zig");

const Tracy = @import("../Core/Tracy.zig");

pub const PanelOpen = struct {
    mAssetHandlePanel: bool,
    mCSEditorPanel: bool,
    mComponentsPanel: bool,
    mContentBrowserPanel: bool,
    mScenePanel: bool,
    mScriptsPanel: bool,
    mStatsPanel: bool,
    mViewportPanel: bool,
    mPreviewPanel: bool,
};

//editor imgui stuff
_AssetHandlePanel: AssetHandlePanel = .{},
_ComponentsPanel: ComponentsPanel = .{},
_ContentBrowserPanel: ContentBrowserPanel = .{},
_CSEditorPanel: CSEditorPanel = .{},
_ScenePanel: ScenePanel = .{},
_ScriptsPanel: ScriptsPanel = .{},
_StatsPanel: StatsPanel = .{},
_ToolbarPanel: ToolbarPanel = .{},
_ViewportPanel: ViewportPanel = .{},
_SceneSpecList: std.ArrayList(SceneSpecPanel) = .{},

//editor stuff
mEditorSceneManager: SceneManager = .{},
mOverlayScene: SceneLayer = .{},
mGameScene: SceneLayer = .{},
mEditorEditorEntity: Entity = .{},
mEditorEditorPlayer: Player = .{},
mEditorViewportEntity: Entity = .{},
mEditorViewportPlayer: Player = .{},
mEditorFont: AssetHandle = .{},

//not editor stuff
mWindow: *Window = undefined,
mImgui: ImGui = .{},
mGameSceneManager: SceneManager = .{},
mPlaySceneManager: SceneManager = .{},
mActiveSceneManager: *SceneManager = undefined,
mPlayerManager: PlayerManager = .{},

const EditorProgram = @This();

pub fn Init(self: *EditorProgram, window: *Window, engine_context: *EngineContext) !void {
    const engine_allocator = engine_context.EngineAllocator();

    self.mWindow = window;

    try self.mEditorSceneManager.Init(self.mWindow.GetWidth(), self.mWindow.GetHeight(), engine_allocator);
    try self.mGameSceneManager.Init(self.mWindow.GetWidth(), self.mWindow.GetHeight(), engine_allocator);
    try self.mPlaySceneManager.Init(self.mWindow.GetWidth(), self.mWindow.GetHeight(), engine_allocator);
    self.mActiveSceneManager = &self.mGameSceneManager;

    try self.mImgui.Init(self.mWindow);

    self._ComponentsPanel.Init();
    try self._ContentBrowserPanel.Init(engine_context);
    self._CSEditorPanel.Init(engine_allocator);
    try self._ToolbarPanel.Init(engine_context);
    self._ViewportPanel.Init(self.mWindow.GetWidth(), self.mWindow.GetHeight());

    self.mOverlayScene = try self.mEditorSceneManager.NewScene(engine_context, .OverlayLayer);
    self.mGameScene = try self.mEditorSceneManager.NewScene(engine_context, .GameLayer);

    self.mEditorEditorEntity = try self.mGameScene.CreateEntity(engine_allocator);
    self.mEditorViewportEntity = try self.mGameScene.CreateEntity(engine_allocator);

    try GameObjectUtils.AddScriptToEntity(engine_context, self.mEditorViewportEntity, "assets/scripts/EditorCameraInput.zig", .Eng);

    self.mEditorViewportPlayer = self.mEditorSceneManager.CreatePlayer(engine_context);
    self.mEditorEditorPlayer = self.mEditorSceneManager.CreatePlayer(engine_context);

    self.mEditorViewportEntity.GetComponent(TransformComponent).?.Translation = Vec3f32{ 0.0, 0.0, 15.0 };
    self.mEditorEditorEntity.GetComponent(TransformComponent).?.Translation = Vec3f32{ 0.0, 0.0, 15.0 };

    self.mEditorEditorPlayer.GetComponent(PlayerLens).?.SetViewportSize(self.mWindow.GetWidth(), self.mWindow.GetHeight());
    self.mEditorViewportPlayer.GetComponent(PlayerLens).?.SetViewportSize(self.mWindow.GetWidth(), self.mWindow.GetHeight());

    try self.mEditorViewportEntity.AddComponent(PlayerSlotComponent{});
    self.mEditorViewportEntity.Possess(self.mEditorViewportPlayer);
    self.mEditorViewportPlayer.Possess(self.mEditorViewportEntity);
}

pub fn Deinit(self: *EditorProgram, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("EditorProgram::Deinit", @src());
    defer zone.Deinit();

    try self.mGameSceneManager.Deinit(engine_context);
    try self.mPlaySceneManager.Deinit(engine_context);
    try self.mEditorSceneManager.Deinit(engine_context);
    self._ContentBrowserPanel.Deinit(engine_context);
    self._CSEditorPanel.Deinit();
    self.mImgui.Deinit();
}

//Note other systems to consider in the on update loop
//that isnt there already:
//particles
//handling the loading and unloading of assets and scene transitions
//debug/profiling
pub fn OnUpdate(self: *EditorProgram, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("Program OnUpdate", @src());
    defer zone.Deinit();

    const engine_allocator = engine_context.EngineAllocator();
    //-------------Inputs Begin------------------
    {
        const input_zone = Tracy.ZoneInit("Inputs Section", @src());
        defer input_zone.Deinit();

        //Human Inputs
        self.mWindow.PollInputEvents();
        try engine_context.mSystemEventManager.ProcessEvents(engine_context, .EC_Input);

        //AI Inputs
    }
    //---------------Inputs End-------------------

    //-------------Physics Begin-----------------
    {
        const physics_zone = Tracy.ZoneInit("Physics Section", @src());
        defer physics_zone.Deinit();
        if (self._ToolbarPanel.mState == .Play) {
            try engine_context.mPhysicsManager.OnUpdate(engine_context, &self.mPlaySceneManager);
        }
    }
    //-------------Physics End-------------------

    //-------------Game Logic Begin--------------
    {
        const game_logic_zone = Tracy.ZoneInit("Game Logic Section", @src());
        defer game_logic_zone.Deinit();

        if (self._ToolbarPanel.mState == .Play) {
            _ = try ScriptsProcessor.RunEntityScript(engine_context, OnUpdateScript, &self.mPlaySceneManager, .{});
        }
        _ = try ScriptsProcessor.RunEntityScript(engine_context, OnUpdateScript, &self.mEditorSceneManager, .{});
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
        try engine_context.mPhysicsManager.UpdateWorldTransforms(engine_context, &self.mGameSceneManager);
        try engine_context.mPhysicsManager.UpdateWorldTransforms(engine_context, &self.mEditorSceneManager);
        if (self._ToolbarPanel.mState == .Play) {
            try engine_context.mPhysicsManager.UpdateWorldTransforms(engine_context, &self.mPlaySceneManager);
        }
    }
    //---------------End World Transform Update ------------

    //---------Render Begin-------------
    {
        const render_zone = Tracy.ZoneInit("Render Section", @src());
        defer render_zone.Deinit();
        if (engine_context.mIsMinimized == false) {
            self.mImgui.Begin();
            Dockspace.Begin();

            try self._ContentBrowserPanel.OnImguiRender(engine_context);
            try self._AssetHandlePanel.OnImguiRender(engine_context);
            try self._ScenePanel.OnImguiRender(engine_context, self.mActiveSceneManager);
            for (self._SceneSpecList.items) |*scene_spec_panel| {
                try scene_spec_panel.OnImguiRender(engine_context);
            }

            try self._ComponentsPanel.OnImguiRender(engine_context);
            try self._ScriptsPanel.OnImguiRender(engine_context);
            try self._CSEditorPanel.OnImguiRender(engine_context);

            try self.RenderPlayerLens(engine_context);
            try self.ViewportPlayRender(engine_context);

            try self._StatsPanel.OnImguiRender(engine_context.mDT, engine_context.mRenderer.GetRenderStats());

            try self._ToolbarPanel.OnImguiRender(engine_context, &self.mGameSceneManager);
            const opens = PanelOpen{
                .mAssetHandlePanel = self._AssetHandlePanel._P_Open,
                .mCSEditorPanel = self._CSEditorPanel.mP_Open,
                .mComponentsPanel = self._ComponentsPanel._P_Open,
                .mContentBrowserPanel = self._ContentBrowserPanel.mIsVisible,
                .mPreviewPanel = self._ViewportPanel.mP_OpenPlay,
                .mScenePanel = self._ScenePanel.mIsVisible,
                .mScriptsPanel = self._ScriptsPanel._P_Open,
                .mStatsPanel = self._StatsPanel._P_Open,
                .mViewportPanel = self._ViewportPanel.mP_OpenViewport,
            };

            try Dockspace.OnImguiRender(engine_context, opens);

            try engine_context.mImguiEventManager.ProcessEvents(engine_context);

            Dockspace.End();
            self.mImgui.End();
        }
    }
    //--------------Render End-------------------

    //--------------Audio Begin------------------
    {
        const audio_zone = Tracy.ZoneInit("Audio Section", @src());
        defer audio_zone.Deinit();
    }
    //--------------Audio End--------------------

    //--------------Networking Begin-------------
    {
        const networking_zone = Tracy.ZoneInit("Networking Section", @src());
        defer networking_zone.Deinit();
    }
    //--------------Networking End---------------

    //-----------------Start End of Frame-----------------
    {
        const end_frame_zone = Tracy.ZoneInit("End Frame Section", @src());
        defer end_frame_zone.Deinit();

        //swap buffers
        engine_context.mRenderer.SwapBuffers();

        //Process window events
        try engine_context.mSystemEventManager.ProcessEvents(engine_context, .EC_Window);

        //handle any closed scene spec panels
        self.CleanSceneSpecs(engine_context.EngineAllocator());

        //handle deleted objects this frame
        try engine_context.mGameEventManager.ProcessEvents(engine_context, .EC_EndOfFrame);

        try self.mGameSceneManager.ProcessRemovedObj(engine_context);
        try self.mEditorSceneManager.ProcessRemovedObj(engine_context);
        try engine_context.mAssetManager.ProcessDestroyedAssets(engine_context);

        //end of frame resets
        engine_context.mSystemEventManager.EventsReset(engine_allocator, .ClearRetainingCapacity);
        engine_context.mGameEventManager.EventsReset(engine_allocator, .ClearRetainingCapacity);
        engine_context.mImguiEventManager.EventsReset(engine_allocator, .ClearRetainingCapacity);
    }
    //-----------------End End of Frame-------------------

}

pub fn OnImguiEvent(self: *EditorProgram, event: *ImguiEvent, engine_context: *EngineContext) !void {
    const engine_allocator = engine_context.EngineAllocator();
    switch (event.*) {
        .ET_TogglePanelEvent => |e| {
            switch (e._PanelType) {
                .AssetHandles => self._AssetHandlePanel.OnTogglePanelEvent(),
                .Components => self._ComponentsPanel.OnTogglePanelEvent(),
                .ContentBrowser => self._ContentBrowserPanel.OnTogglePanelEvent(),
                .CSEditor => self._CSEditorPanel.OnTogglePanelEvent(),
                .Scene => self._ScenePanel.OnTogglePanelEvent(),
                .Scripts => self._ScriptsPanel.OnTogglePanelEvent(),
                .Stats => self._StatsPanel.OnTogglePanelEvent(),
                .Viewport => self._ViewportPanel.OnTogglePanelEventViewport(),
                .PlayPanel => self._ViewportPanel.OnTogglePanelEventPlay(),
                else => @panic("This event has not been handled by this type of panel yet!\n"),
            }
        },
        .ET_NewProjectEvent => |e| {
            if (e.mAbsPath.len > 0) {
                try self._ContentBrowserPanel.OnNewProjectEvent(engine_allocator, e.mAbsPath);
                try engine_context.mAssetManager.OnNewProjectEvent(engine_allocator, e.mAbsPath);
            }
        },
        .ET_OpenProjectEvent => |e| {
            if (e.mAbsPath.len > 0) {
                try self._ContentBrowserPanel.OnOpenProjectEvent(engine_allocator, e.mAbsPath);
                try engine_context.mAssetManager.OnOpenProjectEvent(engine_allocator, e.mAbsPath);
            }
        },
        .ET_NewSceneEvent => |e| {
            _ = try self.mGameSceneManager.NewScene(engine_context, e.mLayerType);
        },
        .ET_SaveSceneEvent => {
            if (self._ScenePanel.mSelectedScene) |scene_layer| {
                try self.mGameSceneManager.SaveScene(engine_context, scene_layer);
            }
        },
        .ET_SaveSceneAsEvent => |e| {
            if (self._ScenePanel.mSelectedScene) |scene_layer| {
                if (e.mAbsPath.len > 0) {
                    try self.mGameSceneManager.SaveSceneAs(engine_context.FrameAllocator(), scene_layer);
                }
            }
        },
        .ET_OpenSceneEvent => |e| {
            if (e.mAbsPath.len > 0) {
                _ = try self.mGameSceneManager.LoadScene(engine_context, e.mAbsPath);
            }
        },
        .ET_MoveSceneEvent => |e| {
            try self.mGameSceneManager.MoveScene(engine_context.FrameAllocator(), e.SceneID, e.NewPos);
        },
        .ET_NewEntityEvent => |e| {
            _ = try self.mGameSceneManager.CreateEntity(engine_allocator, e.SceneID);
        },
        .ET_SelectSceneEvent => |e| {
            self._ScenePanel.OnSelectSceneEvent(e.SelectedScene);
            self._ComponentsPanel.OnSelectSceneEvent(e.SelectedScene);
        },
        .ET_SelectEntityEvent => |e| {
            self._ScenePanel.OnSelectEntityEvent(e.SelectedEntity);
            self._ComponentsPanel.OnSelectEntityEvent(e.SelectedEntity);
            self._ScriptsPanel.OnSelectEntityEvent(e.SelectedEntity);
            self._ViewportPanel.OnSelectEntityEvent(e.SelectedEntity);
        },
        .ET_SelectComponentEvent => |e| {
            try self._CSEditorPanel.OnSelectComponentEvent(e.mEditorWindow);
        },
        .ET_SelectScriptEvent => |e| {
            try self._CSEditorPanel.OnSelectScriptEvent(e.mEditorWindow);
        },
        .ET_ViewportResizeEvent => |e| {
            self.mEditorViewportPlayer.GetComponent(PlayerLens).?.SetViewportSize(e.mWidth, e.mHeight);

            //we must also resize the in game cameras to match the viewport since we are not using the play panel
            if (!self._ViewportPanel.mP_OpenPlay) {
                try self.mGameSceneManager.OnViewportResize(engine_context.FrameAllocator(), e.mWidth, e.mHeight);
            }
        },
        .ET_PlayPanelResizeEvent => |e| {
            //we dont need to check if play panel is being used or not because if the panel was resized its has to be open i think?
            if (self._ViewportPanel.mP_OpenPlay) {
                try self.mGameSceneManager.OnViewportResize(engine_context.FrameAllocator(), e.mWidth, e.mHeight);
            }
        },
        .ET_NewScriptEvent => |e| {
            try self._ContentBrowserPanel.OnNewScriptEvent(engine_context, e);
        },
        .ET_ChangeEditorStateEvent => |e| {
            try self.OnChangeEditorStateEvent(engine_context, e);
        },
        .ET_OpenSceneSpecEvent => |e| {
            const new_scene_spec_panel = try SceneSpecPanel.Init(e.mSceneLayer);
            try self._SceneSpecList.append(engine_context.EngineAllocator(), new_scene_spec_panel);
        },
        .ET_SaveEntityEvent => {
            if (self._ScenePanel.mSelectedEntity) |selected_entity| {
                try self.mGameSceneManager.SaveEntity(engine_context.FrameAllocator(), selected_entity);
            }
        },
        .ET_SaveEntityAsEvent => |e| {
            if (self._ScenePanel.mSelectedEntity) |selected_entity| {
                if (e.mAbsPath.len > 0) {
                    try self.mGameSceneManager.SaveEntityAs(engine_context.FrameAllocator(), selected_entity, e.mAbsPath);
                }
            }
        },
        .ET_DeleteEntityEvent => |e| {
            self._ScenePanel.OnDeleteEntity(e.mEntity);
            self._ComponentsPanel.OnDeleteEntity(e.mEntity);
            self._ScriptsPanel.OnDeleteEntity(e.mEntity);
            self._ViewportPanel.OnDeleteEntity(e.mEntity);
        },
        .ET_DeleteSceneEvent => |e| {
            self._ScenePanel.OnDeleteScene(e.mScene);
            self._ComponentsPanel.OnDeleteScene(e.mScene);
        },
        .ET_RmEntityCompEvent => |e| {
            //if the component has an editor window open close it
            try self._CSEditorPanel.RmEntityComp(e.mComponent_ptr);
        },
        else => std.debug.print("This event has not been handled by editor program!\n", .{}),
    }
}

pub fn OnGameEvent(self: *EditorProgram, engine_context: *EngineContext, event: *GameEvent) !void {
    switch (event.*) {
        .ET_DestroyEntityEvent => |e| {
            try self.mGameSceneManager.DestroyEntity(engine_context.EngineAllocator(), e.mEntity);
        },
        .ET_DestroySceneEvent => |e| {
            const scene = self.mGameSceneManager.GetSceneLayer(e.mSceneID);
            try self.mGameSceneManager.RemoveScene(engine_context, scene);
        },
        .ET_RmEntityCompEvent => |e| {
            try self.mGameSceneManager.RmEntityComp(engine_context.EngineAllocator(), e.mEntityID, e.mComponentType);
        },
        .ET_RmSceneCompEvent => |e| {
            try self.mGameSceneManager.RmSceneComp(engine_context.EngineAllocator(), e.mSceneID, e.mComponentType);
        },
        else => std.debug.print("This event has not been handled by editor program yet!\n", .{}),
    }
}

pub fn OnChangeEditorStateEvent(self: *EditorProgram, engine_context: *EngineContext, event: ChangeEditorStateEvent) !void {
    if (event.mEditorState == .Play) { //the play button was pressed
        try self.mGameSceneManager.Copy(engine_context, self.mPlaySceneManager);
        const new_player = try self.mPlaySceneManager.CreatePlayer(engine_context);
        const start_entity = self._ToolbarPanel.mStartEntity.?;
        const start_entity_uuid = start_entity.GetComponent(EntityUUIDComponent);
    } else { //stop button was pressed
        self._ScenePanel.OnSelectEntityEvent(null);
        self._ComponentsPanel.OnSelectEntityEvent(null);
        self._ScriptsPanel.OnSelectEntityEvent(null);
        self._ViewportPanel.OnSelectEntityEvent(null);

        self._ToolbarPanel.mStartEntity = null;

        try self.mGameSceneManager.ReloadAllScenes(engine_context);
    }
}

pub fn OnInputPressedEvent(self: *EditorProgram, engine_context: *EngineContext, e: InputPressedEvent) !bool {
    var cont_bool = true;
    if (self._ToolbarPanel.mState == .Play) {
        cont_bool = cont_bool and try ScriptsProcessor.RunEntityScript(engine_context, OnInputPressedScript, &self.mGameSceneManager, .{&e});
    }

    cont_bool = cont_bool and self._ViewportPanel.OnInputPressedEvent(e);

    _ = try ScriptsProcessor.RunEntityScriptEditor(engine_context, OnInputPressedScript, &self.mEditorSceneManager, &self.mGameScene, .{&e});

    //for quick debugging uncomment
    //_ = try ScriptsProcessor.RunEntityScript(engine_context, OnInputPressedScript, &self.mGameSceneManager, .{&e});
    return cont_bool;
}

pub fn OnWindowResize(self: *EditorProgram, width: usize, height: usize) !bool {
    self.mEditorEditorPlayer.GetComponent(PlayerLens).?.SetViewportSize(width, height);
    return true;
}

fn CleanSceneSpecs(self: *EditorProgram, engine_allocator: std.mem.Allocator) void {
    const zone = Tracy.ZoneInit("Clean Scene Specs", @src());
    defer zone.Deinit();
    var end_index: usize = self._SceneSpecList.items.len;
    var i: usize = 0;

    while (i < end_index) {
        if (self._SceneSpecList.items[i].mPOpen == false) {
            self._SceneSpecList.items[i] = self._SceneSpecList.items[end_index - 1];
            end_index -= 1;
        } else {
            i += 1;
        }
    }
    self._SceneSpecList.shrinkAndFree(engine_allocator, end_index);
}

fn RenderPlayerLens(self: *EditorProgram, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("Render Bufferss", @src());
    defer zone.Deinit();

    const frame_allocator = engine_context.FrameAllocator();

    //get all the active lens components with their entities transform component
    var lens_components = try std.ArrayList(*PlayerLens).initCapacity(frame_allocator, 1);
    var transform_components = try std.ArrayList(*TransformComponent).initCapacity(frame_allocator, 1);

    lens_components.append(frame_allocator, self.mEditorViewportPlayer.GetComponent(PlayerLens).?);
    transform_components.append(frame_allocator, self.mEditorViewportEntity.GetComponent(TransformComponent).?);

    const player_slot_entites = self.mPlaySceneManager.GetEntityGroup(frame_allocator, .{ .Component = PlayerSlotComponent });
    for (player_slot_entites.items) |entity_id| {
        const entity = self.mPlaySceneManager.GetEntity(entity_id);
        const player_slot_component = entity.GetComponent(PlayerSlotComponent).?;
        if (player_slot_component.mPlayerEntity.mPlayerID != Player.NullPlayer) {
            lens_components.append(frame_allocator, player_slot_component.mPlayerEntity.GetComponent(PlayerLens).?);
            transform_components.append(frame_allocator, entity.GetComponent(TransformComponent).?);
        }
    }

    for (0..lens_components.items.len) |i| {
        const lens_component = lens_components.items[i];
        const transform_component = transform_components.items[i];

        const world_rot = transform_component.GetWorldRotation();
        const world_pos = transform_component.GetWorldPosition();
        const lens_offset_pos = lens_component.OffsetPosition;
        const lens_offset_rot = lens_component.OffsetRotation;

        const final_rot = LinAlg.QuatMulQuat(world_rot, lens_offset_rot);
        const final_pos = Vec3f32{ world_pos[0] + lens_offset_pos[0], world_pos[1] + lens_offset_pos[1], world_pos[2] + lens_offset_pos[2] };

        try engine_context.mRenderer.OnUpdate(
            engine_context,
            &self.mGameSceneManager,
            .{
                .mRotation = [4]f32{ final_rot[0], final_rot[1], final_rot[2], final_rot[3] }, //this is in (w, x, y, z) format
                .mPosition = [3]f32{ final_pos[0], final_pos[1], final_pos[2] }, //this is in (x, y, z) format
                .mPerspectiveFar = lens_component.mPerspectiveFar,
                .mResolutionWidth = @floatFromInt(lens_component.mViewportWidth),
                .mResolutionHeight = @floatFromInt(lens_component.mViewportHeight),
                .mAspectRatio = lens_component.mAspectRatio,
                .mFOV = lens_component.mPerspectiveFOVRad,
            },
            .{
                .FrameBuffer = lens_component.mViewportFrameBuffer,
                .VertexArray = lens_component.mViewportVertexArray,
                .VertexBuffer = lens_component.mViewportVertexBuffer,
            },
            0b1,
        );
    }
}

fn ViewportPlayRender(self: *EditorProgram, engine_context: *EngineContext) !void {
    const frame_allocator = engine_context.FrameAllocator();

    var viewport_framebuffers = std.ArrayList(FrameBuffer){};
    var viewport_area_rects = std.ArrayList(Vec4f32){};

    if (self._ToolbarPanel.mState == .Stop) {
        const lens_component = self.mEditorViewportPlayer.GetComponent(PlayerLens).?;
        viewport_framebuffers.append(frame_allocator, lens_component.mFrameBuffer);
        viewport_area_rects.append(frame_allocator, lens_component.mAreaRect);
    } else { //Toolbar panel is in play mode
        const player_ids = self.mPlaySceneManager.GetPlayerGroup(frame_allocator, .{ .Component = PossessComponent });
        for (player_ids.items) |player_id| {
            const player = self.mPlayerManager.GetPlayer(player_id);
            const possess_component = player.GetComponent(PossessComponent);
            if (possess_component.mPossessedEntity) {
                const lens_component = player.GetComponent(PlayerLens);
                viewport_framebuffers.append(frame_allocator, lens_component.mFrameBuffer);
                viewport_area_rects.append(frame_allocator, lens_component.mAreaRect);
            }
        }
    }

    self._ViewportPanel.OnImguiRenderViewport(engine_context, viewport_framebuffers, viewport_area_rects);

    if (self._ViewportPanel.mP_OpenPlay) {
        var play_framebuffers = std.ArrayList(FrameBuffer){};
        var play_area_rects = std.ArrayList(Vec4f32){};

        if (self._ToolbarPanel.mState == .Stop) {
            if (self._ToolbarPanel.mStartEntity) |entity| {
                if (entity.GetComponent(PlayerSlotComponent)) |slot_component| {
                    if (slot_component.mPlayerEntity) |player| {
                        const lens_component = player.GetComponent(PlayerLens);
                        play_framebuffers.append(frame_allocator, lens_component.mFrameBuffer);
                        play_area_rects.append(frame_allocator, lens_component.mAreaRect);
                    }
                }
            }
        } else { //Toolbar panel is in play mode
            const lens_component = self.mEditorViewportPlayer.GetComponent(PlayerLens).?;
            viewport_framebuffers.append(frame_allocator, lens_component.mFrameBuffer);
            viewport_area_rects.append(frame_allocator, lens_component.mAreaRect);
        }

        self._ViewportPanel.OnImguiRenderPlay(engine_context, viewport_framebuffers, viewport_area_rects);
    }
}
