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

const EntityComponents = @import("../GameObjects/Components.zig");
const CameraComponent = EntityComponents.CameraComponent;
const TransformComponent = EntityComponents.TransformComponent;
const OnInputPressedScript = EntityComponents.OnInputPressedScript;
const OnUpdateScript = EntityComponents.OnUpdateScript;
const PlayerSlotComponent = EntityComponents.PlayerSlotComponent;
const GameObjectUtils = @import("../GameObjects/GameObjectUtils.zig");

const SceneComponents = @import("../Scene/SceneComponents.zig");
const SceneComponent = SceneComponents.SceneComponent;
const OnSceneStartScript = SceneComponents.OnSceneStartScript;

const PlayerComponents = @import("../Players/Components.zig");
const ControllerComponent = PlayerComponents.ControllerComponent;

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
mEditorViewportEntity: Entity = .{},
mEditorFont: AssetHandle = .{},

//not editor stuff
mWindow: *Window = undefined,
mImgui: ImGui = .{},
mGameSceneManager: SceneManager = .{},
mFrameAllocator: std.mem.Allocator = undefined,
mPlayerManager: PlayerManager = .{},

const EditorProgram = @This();

pub fn Init(self: *EditorProgram, window: *Window, engine_context: *EngineContext) !void {
    const engine_allocator = engine_context.mEngineAllocator;

    self.mWindow = window;

    try self.mEditorSceneManager.Init(self.mWindow.GetWidth(), self.mWindow.GetHeight(), engine_allocator);
    try self.mGameSceneManager.Init(self.mWindow.GetWidth(), self.mWindow.GetHeight(), engine_allocator);

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

    const viewport_transform_component = self.mEditorViewportEntity.GetComponent(TransformComponent).?;
    viewport_transform_component.SetTranslation(Vec3f32{ 0.0, 0.0, 15.0 });

    const camera_transform_component = self.mEditorEditorEntity.GetComponent(TransformComponent).?;
    camera_transform_component.SetTranslation(Vec3f32{ 0.0, 0.0, 15.0 });

    //setup the viewport camera
    var new_camera_component = CameraComponent{
        .mViewportFrameBuffer = try FrameBuffer.Init(engine_allocator, &[_]TextureFormat{.RGBA8}, .None, 1, false, self._ViewportPanel.mViewportWidth, self._ViewportPanel.mViewportHeight),
        .mViewportVertexArray = VertexArray.Init(),
        .mViewportVertexBuffer = VertexBuffer.Init(@sizeOf([4][2]f32)),
        .mViewportIndexBuffer = undefined,
        .mViewportWidth = self._ViewportPanel.mViewportWidth,
        .mViewportHeight = self._ViewportPanel.mViewportHeight,
    };

    const shader_asset = try engine_context.mRenderer.GetSDFShader(engine_context);
    try new_camera_component.mViewportVertexBuffer.SetLayout(engine_allocator, shader_asset.GetLayout());
    new_camera_component.mViewportVertexBuffer.SetStride(shader_asset.GetStride());

    var index_buffer_data = [6]u32{ 0, 1, 2, 2, 3, 0 };
    new_camera_component.mViewportIndexBuffer = IndexBuffer.Init(index_buffer_data[0..], 6);

    var data_vertex_buffer = [4][2]f32{ [2]f32{ -1.0, -1.0 }, [2]f32{ 1.0, -1.0 }, [2]f32{ 1.0, 1.0 }, [2]f32{ -1.0, 1.0 } };
    new_camera_component.mViewportVertexBuffer.SetData(&data_vertex_buffer[0][0], @sizeOf([4][2]f32), 0);
    try new_camera_component.mViewportVertexArray.AddVertexBuffer(engine_allocator, new_camera_component.mViewportVertexBuffer);
    new_camera_component.mViewportVertexArray.SetIndexBuffer(new_camera_component.mViewportIndexBuffer);

    new_camera_component.SetViewportSize(self._ViewportPanel.mViewportWidth, self._ViewportPanel.mViewportHeight);
    _ = try self.mEditorViewportEntity.AddComponent(CameraComponent, new_camera_component);

    try GameObjectUtils.AddScriptToEntity(self.mEditorViewportEntity, "assets/scripts/EditorCameraInput.zig", .Eng, engine_context);

    //setup the full screen editor camera
    var new_camera_component_camera = CameraComponent{
        .mViewportFrameBuffer = try FrameBuffer.Init(engine_allocator, &[_]TextureFormat{.RGBA8}, .None, 1, false, self.mWindow.GetWidth(), self.mWindow.GetHeight()),
        .mViewportVertexArray = VertexArray.Init(),
        .mViewportVertexBuffer = VertexBuffer.Init(@sizeOf([4][2]f32)),
        .mViewportIndexBuffer = undefined,
    };

    const shader_asset_camera = try engine_context.mRenderer.GetSDFShader(engine_context);
    try new_camera_component_camera.mViewportVertexBuffer.SetLayout(engine_allocator, shader_asset_camera.GetLayout());
    new_camera_component_camera.mViewportVertexBuffer.SetStride(shader_asset_camera.GetStride());

    var index_buffer_data_camera = [6]u32{ 0, 1, 2, 2, 3, 0 };
    new_camera_component_camera.mViewportIndexBuffer = IndexBuffer.Init(index_buffer_data_camera[0..], 6);

    var data_vertex_buffer_camera = [4][2]f32{ [2]f32{ -1.0, -1.0 }, [2]f32{ 1.0, -1.0 }, [2]f32{ 1.0, 1.0 }, [2]f32{ -1.0, 1.0 } };
    new_camera_component_camera.mViewportVertexBuffer.SetData(&data_vertex_buffer_camera[0][0], @sizeOf([4][2]f32), 0);
    try new_camera_component_camera.mViewportVertexArray.AddVertexBuffer(engine_allocator, new_camera_component_camera.mViewportVertexBuffer);
    new_camera_component_camera.mViewportVertexArray.SetIndexBuffer(new_camera_component_camera.mViewportIndexBuffer);

    new_camera_component_camera.SetViewportSize(self.mWindow.GetWidth(), self.mWindow.GetHeight());
    _ = try self.mEditorEditorEntity.AddComponent(CameraComponent, new_camera_component_camera);
}

pub fn Deinit(self: *EditorProgram, engine_context: *EngineContext) !void {
    try self.mGameSceneManager.Deinit();
    try self.mEditorSceneManager.Deinit();
    self._ContentBrowserPanel.Deinit(engine_context);
    self._CSEditorPanel.Deinit();
    self.mImgui.Deinit();
}

//Note other systems to consider in the on update loop
//that isnt there already:
//particles
//handling the loading and unloading of assets and scene transitions
//debug/profiling
pub fn OnUpdate(self: *EditorProgram, dt: f32, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("Program OnUpdate", @src());
    defer zone.Deinit();

    const engine_allocator = engine_context.mEngineAllocator;

    //-------------Inputs Begin------------------
    {
        const input_zone = Tracy.ZoneInit("Inputs Section", @src());
        defer input_zone.Deinit();

        //Human Inputs
        self.mWindow.PollInputEvents();
        engine_context.mInputManager.OnUpdate();
        try engine_context.mSystemEventManager.ProcessEvents(.EC_Input);
        if (self._ToolbarPanel.mState == .Play) {
            _ = try ScriptsProcessor.RunEntityScript(engine_context, OnUpdateScript, &self.mGameSceneManager, .{});
        }
        _ = try ScriptsProcessor.RunEntityScriptEditor(engine_context, OnUpdateScript, &self.mEditorSceneManager, &self.mGameScene, .{});

        //for debugging uncomment this
        //_ = try ScriptsProcessor.RunEntityScript(&self.mEditorSceneManager, OnUpdateInputScript, .{}, self.mFrameAllocator);

        //AI Inputs
    }
    //---------------Inputs End-------------------

    //-------------Physics Begin-----------------
    {
        const physics_zone = Tracy.ZoneInit("Physics Section", @src());
        defer physics_zone.Deinit();
    }
    //-------------Physics End-------------------

    //-------------Game Logic Begin--------------
    {
        const game_logic_zone = Tracy.ZoneInit("Game Logic Section", @src());
        defer game_logic_zone.Deinit();
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
    //-------------End Assets Update

    //---------Render Begin-------------
    {
        const render_zone = Tracy.ZoneInit("Render Section", @src());
        defer render_zone.Deinit();

        self.mImgui.Begin();
        Dockspace.Begin();

        try self._ContentBrowserPanel.OnImguiRender(engine_context);
        try self._AssetHandlePanel.OnImguiRender(engine_context);

        try self._ScenePanel.OnImguiRender(engine_context, &self.mGameSceneManager);

        for (self._SceneSpecList.items) |*scene_spec_panel| {
            try scene_spec_panel.OnImguiRender(engine_context);
        }
        try self._ComponentsPanel.OnImguiRender(engine_context);
        try self._ScriptsPanel.OnImguiRender(engine_context);
        try self._CSEditorPanel.OnImguiRender(engine_context.mFrameAllocator);

        try self.RenderBuffers(engine_context);

        try self._StatsPanel.OnImguiRender(dt, Renderer.GetRenderStats());

        try self._ToolbarPanel.OnImguiRender(&self.mGameSceneManager, engine_context.mFrameAllocator);

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

        try engine_context.mImguiEventManager.ProcessEvents(engine_allocator);

        Dockspace.End();
        self.mImgui.End();
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
        try engine_context.mSystemEventManager.ProcessEvents(.EC_Window);

        //handle any closed scene spec panels
        self.CleanSceneSpecs(engine_context.mEngineAllocator);

        //handle deleted objects this frame
        try engine_context.mGameEventManager.ProcessEvents(.EC_EndOfFrame, engine_context.mFrameAllocator);

        try self.mGameSceneManager.ProcessRemovedObj();
        try self.mEditorSceneManager.ProcessRemovedObj();
        try engine_context.mAssetManager.ProcessDestroyedAssets();
        try self.mPlayerManager.ProcessDestroyedPlayers();

        //end of frame resets
        engine_context.mSystemEventManager.EventsReset(engine_allocator);
        engine_context.mGameEventManager.EventsReset(engine_allocator);
        engine_context.mImguiEventManager.EventsReset(engine_allocator);
    }
    //-----------------End End of Frame-------------------

}

pub fn OnImguiEvent(self: *EditorProgram, event: *ImguiEvent, engine_context: *EngineContext) !void {
    const engine_allocator = engine_context.mEngineAllocator;
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
            if (e.Path.len > 0) {
                try self._ContentBrowserPanel.OnNewProjectEvent(engine_allocator, e.Path);
                engine_context.mAssetManager.OnNewProjectEvent(engine_allocator, e.Path);
            }
        },
        .ET_OpenProjectEvent => |e| {
            if (e.Path.len > 0) {
                try self._ContentBrowserPanel.OnOpenProjectEvent(engine_allocator, e.Path);
                engine_context.mAssetManager.OnOpenProjectEvent(engine_allocator, e.Path);
            }
        },
        .ET_NewSceneEvent => |e| {
            _ = try self.mGameSceneManager.NewScene(engine_context, e.mLayerType);
        },
        .ET_SaveSceneEvent => {
            if (self._ScenePanel.mSelectedScene) |scene_layer| {
                try self.mGameSceneManager.SaveScene(scene_layer, engine_context);
            }
        },
        .ET_SaveSceneAsEvent => |e| {
            if (self._ScenePanel.mSelectedScene) |scene_layer| {
                if (e.AbsPath.len > 0) {
                    const scene_component = scene_layer.GetComponent(SceneComponent).?;
                    const rel_path = engine_context.mAssetManager.GetRelPath(e.AbsPath);
                    _ = try std.fs.createFileAbsolute(e.AbsPath, .{});
                    scene_component.mSceneAssetHandle = engine_context.mAssetManager.GetAssetHandleRef(engine_context.mEngineAllocator, rel_path, .Prj);
                    try self.mGameSceneManager.SaveSceneAs(scene_layer, e.AbsPath, engine_context.mFrameAllocator);
                }
            }
        },
        .ET_OpenSceneEvent => |e| {
            if (e.Path.len > 0) {
                _ = try self.mGameSceneManager.LoadScene(e.Path, self._EngineAllocator, self.mFrameAllocator);
            }
        },
        .ET_MoveSceneEvent => |e| {
            try self.mGameSceneManager.MoveScene(e.SceneID, e.NewPos);
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
            const viewport_camera_component = self.mEditorViewportEntity.GetComponent(CameraComponent).?;
            viewport_camera_component.SetViewportSize(e.mWidth, e.mHeight);

            //we must also resize the in game cameras to match the viewport since we are not using the play panel
            if (!self._ViewportPanel.mP_OpenPlay) {
                try self.mGameSceneManager.OnViewportResize(e.mWidth, e.mHeight, engine_context.mFrameAllocator);
            }
        },
        .ET_PlayPanelResizeEvent => |e| {
            //we dont need to check if play panel is being used or not because if the panel was resized its has to be open i think?
            try self.mGameSceneManager.OnViewportResize(e.mWidth, e.mHeight, engine_context.mFrameAllocator);
        },
        .ET_NewScriptEvent => |e| {
            try self._ContentBrowserPanel.OnNewScriptEvent(engine_context, e);
        },
        .ET_ChangeEditorStateEvent => |e| {
            try self.OnChangeEditorStateEvent(e, engine_context.mFrameAllocator);
        },
        .ET_OpenSceneSpecEvent => |e| {
            const new_scene_spec_panel = try SceneSpecPanel.Init(e.mSceneLayer);
            try self._SceneSpecList.append(engine_context.mEngineAllocator, new_scene_spec_panel);
        },
        .ET_SaveEntityEvent => {
            if (self._ScenePanel.mSelectedEntity) |selected_entity| {
                try self.mGameSceneManager.SaveEntity(selected_entity, engine_context.mFrameAllocator);
            }
        },
        .ET_SaveEntityAsEvent => |e| {
            if (self._ScenePanel.mSelectedEntity) |selected_entity| {
                if (e.Path.len > 0) {
                    try self.mGameSceneManager.SaveEntityAs(selected_entity, e.Path, engine_context.mFrameAllocator);
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

pub fn OnGameEvent(self: *EditorProgram, event: *GameEvent, frame_allocator: std.mem.Allocator) !void {
    switch (event.*) {
        .ET_DestroyEntityEvent => |e| {
            try self.mGameSceneManager.DestroyEntity(e.mEntity);
        },
        .ET_DestroySceneEvent => |e| {
            const scene = self.mGameSceneManager.GetSceneLayer(e.mSceneID);
            try self.mGameSceneManager.RemoveScene(scene, frame_allocator);
        },
        .ET_RmEntityCompEvent => |e| {
            try self.mGameSceneManager.RmEntityComp(e.mEntityID, e.mComponentType);
        },
        .ET_RmSceneCompEvent => |e| {
            try self.mGameSceneManager.RmSceneComp(e.mSceneID, e.mComponentType);
        },
        else => std.debug.print("This event has not been handled by editor program yet!\n", .{}),
    }
}

pub fn OnChangeEditorStateEvent(self: *EditorProgram, event: ChangeEditorStateEvent, frame_allocator: std.mem.Allocator) !void {
    if (event.mEditorState == .Play) { //the play button was pressed so now we playing
        try self.mGameSceneManager.SaveAllScenes(frame_allocator);
        _ = try ScriptsProcessor.RunSceneScript(frame_allocator, &self.mGameSceneManager, OnSceneStartScript, .{});
    } else { //stop
        try self.mGameSceneManager.ReloadAllScenes(frame_allocator);

        self._ScenePanel.OnSelectEntityEvent(null);
        self._ComponentsPanel.OnSelectEntityEvent(null);
        self._ScriptsPanel.OnSelectEntityEvent(null);
        self._ViewportPanel.OnSelectEntityEvent(null);

        self._ToolbarPanel.mStartEntity = null;
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
    self.mEditorEditorEntity.GetComponent(CameraComponent).?.SetViewportSize(width, height);
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

fn RenderBuffers(self: *EditorProgram, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("Render Bufferss", @src());
    defer zone.Deinit();

    var camera_components = try std.ArrayList(*CameraComponent).initCapacity(self.mFrameAllocator, 1);
    var transform_components = try std.ArrayList(*TransformComponent).initCapacity(self.mFrameAllocator, 1);

    if (self._ToolbarPanel.mState == .Stop) { //editor state is stopped
        const editor_camera_component = self.mEditorViewportEntity.GetComponent(CameraComponent).?;
        const editor_camera_transform = self.mEditorViewportEntity.GetComponent(TransformComponent).?;

        try engine_context.mRenderer.OnUpdate(&self.mGameSceneManager, editor_camera_component, editor_camera_transform, self.mFrameAllocator, 0b1);

        try camera_components.append(self.mFrameAllocator, editor_camera_component);
        try transform_components.append(self.mFrameAllocator, editor_camera_transform);

        try self._ViewportPanel.OnImguiRenderViewport(engine_context, camera_components, transform_components);

        camera_components.clearRetainingCapacity();
        transform_components.clearRetainingCapacity();

        if (self._ViewportPanel.mP_OpenPlay) {
            if (self._ToolbarPanel.mStartEntity) |start_entity| {
                const camera_entity = start_entity.GetCameraEntity();
                if (camera_entity) |entity| {
                    const start_camera_component = entity.GetComponent(CameraComponent).?;
                    const start_transform_component = entity.GetComponent(TransformComponent).?;

                    try engine_context.mRenderer.OnUpdate(&self.mGameSceneManager, start_camera_component, start_transform_component, self.mFrameAllocator, 0b0);

                    try camera_components.append(self.mFrameAllocator, start_camera_component);
                    try transform_components.append(self.mFrameAllocator, start_transform_component);

                    try self._ViewportPanel.OnImguiRenderPlay(engine_context, camera_components);

                    camera_components.clearRetainingCapacity();
                    transform_components.clearRetainingCapacity();
                }
            } else {
                try self._ViewportPanel.OnImguiRenderPlay(engine_context, camera_components);
            }
        }
    } else { //editor state is play
        if (self._ViewportPanel.mP_OpenPlay) {

            //render the viewport
            const editor_camera_component = self.mEditorViewportEntity.GetComponent(CameraComponent).?;
            const editor_camera_transform = self.mEditorViewportEntity.GetComponent(TransformComponent).?;

            try engine_context.mRenderer.OnUpdate(&self.mGameSceneManager, editor_camera_component, editor_camera_transform, self.mFrameAllocator, 0b1);

            try camera_components.append(self.mFrameAllocator, editor_camera_component);
            try transform_components.append(self.mFrameAllocator, editor_camera_transform);

            try self._ViewportPanel.OnImguiRenderViewport(engine_context, camera_components, transform_components);

            camera_components.clearRetainingCapacity();
            transform_components.clearRetainingCapacity();

            //render the play from the camera entity
            const camera_entity = self._ToolbarPanel.mStartEntity.?.GetCameraEntity();
            if (camera_entity) |entity| {
                const start_camera_component = entity.GetComponent(CameraComponent).?;
                const start_transform_component = entity.GetComponent(TransformComponent).?;

                try engine_context.mRenderer.OnUpdate(&self.mGameSceneManager, start_camera_component, start_transform_component, self.mFrameAllocator, 0b0);

                try camera_components.append(self.mFrameAllocator, start_camera_component);
                try transform_components.append(self.mFrameAllocator, start_transform_component);

                try self._ViewportPanel.OnImguiRenderPlay(engine_context, camera_components);

                camera_components.clearRetainingCapacity();
                transform_components.clearRetainingCapacity();
            }
        } else {
            const camera_entity = self._ToolbarPanel.mStartEntity.?.GetCameraEntity();
            if (camera_entity) |entity| {
                const start_camera_component = entity.GetComponent(CameraComponent).?;
                const start_transform_component = entity.GetComponent(TransformComponent).?;

                try engine_context.mRenderer.OnUpdate(&self.mGameSceneManager, start_camera_component, start_transform_component, self.mFrameAllocator, 0b0);

                try camera_components.append(self.mFrameAllocator, start_camera_component);
                try transform_components.append(self.mFrameAllocator, start_transform_component);

                try self._ViewportPanel.OnImguiRenderViewport(engine_context, camera_components, transform_components);

                camera_components.clearRetainingCapacity();
                transform_components.clearRetainingCapacity();
            }
        }
    }
}
