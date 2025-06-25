const std = @import("std");

const Window = @import("../Windows/Window.zig");
const StaticInputContext = @import("../Inputs/Input.zig");
const ScriptsProcessor = @import("../Scripts/ScriptsProcessor.zig");
const Renderer = @import("../Renderer/Renderer.zig");
const Entity = @import("../GameObjects/Entity.zig");

const LinAlg = @import("../Math/LinAlg.zig");
const Vec3f32 = LinAlg.Vec3f32;
const Quatf32 = LinAlg.Quatf32;

const EntityComponents = @import("../GameObjects/Components.zig");
const CameraComponent = EntityComponents.CameraComponent;
const TransformComponent = EntityComponents.TransformComponent;
const OnInputPressedScript = EntityComponents.OnInputPressedScript;
const OnUpdateInputScript = EntityComponents.OnUpdateInputScript;
const GameObjectUtils = @import("../GameObjects/GameObjectUtils.zig");

const SceneComponents = @import("../Scene/SceneComponents.zig");
const SceneComponent = SceneComponents.SceneComponent;
const OnSceneStartScript = SceneComponents.OnSceneStartScript;

const SystemEvent = @import("../Events/SystemEvent.zig").SystemEvent;
const InputPressedEvent = @import("../Events/SystemEvent.zig").InputPressedEvent;
const WindowResizeEvent = @import("../Events/SystemEvent.zig").WindowResizeEvent;
const SystemEventManager = @import("../Events/SystemEventManager.zig");
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const ImguiEventManager = @import("../Events/ImguiEventManager.zig");
const GameEvent = @import("../Events/GameEvent.zig").GameEvent;
const GameEventManager = @import("../Events/GameEventManager.zig");
const ChangeEditorStateEvent = @import("../Events/ImguiEvent.zig").ChangeEditorStateEvent;

const ImGui = @import("../Imgui/Imgui.zig");
const Dockspace = @import("../Imgui/Dockspace.zig");
const AssetHandlePanel = @import("../Imgui/AssethandlePanel.zig");
const ComponentsPanel = @import("../Imgui/ComponentsPanel.zig");
const ContentBrowserPanel = @import("../Imgui/ContentBrowserPanel.zig");
const CSEditorPanel = @import("../Imgui/CSEditorPanel.zig");
const PlayPanel = @import("../Imgui/PlayPanel.zig");
const ScenePanel = @import("../Imgui/ScenePanel.zig");
const ScriptsPanel = @import("../Imgui/ScriptsPanel.zig");
const StatsPanel = @import("../Imgui/StatsPanel.zig");
const ToolbarPanel = @import("../Imgui/ToolbarPanel.zig");
const ViewportPanel = @import("../Imgui/ViewportPanel.zig");
const AssetManager = @import("../Assets/AssetManager.zig");
const SceneSpecPanel = @import("../Imgui/SceneSpecsPanel.zig");

const SceneManager = @import("../Scene/SceneManager.zig");
const SceneLayer = @import("../Scene/SceneLayer.zig");
const EditorState = @import("../Imgui/ToolbarPanel.zig").EditorState;
const FrameBuffer = @import("../FrameBuffers/FrameBuffer.zig");
const TextureFormat = @import("../FrameBuffers/InternalFrameBuffer.zig").TextureFormat;

//editor imgui stuff
_AssetHandlePanel: AssetHandlePanel,
_ComponentsPanel: ComponentsPanel,
_ContentBrowserPanel: ContentBrowserPanel,
_CSEditorPanel: CSEditorPanel,
_PlayPanel: PlayPanel,
_ScenePanel: ScenePanel,
_ScriptsPanel: ScriptsPanel,
_StatsPanel: StatsPanel,
_ToolbarPanel: ToolbarPanel,
_ViewportPanel: ViewportPanel,
_EditorState: EditorState,
_UsePlayPanel: bool,
_SceneSpecList: std.ArrayList(SceneSpecPanel),

//editor stuff
mEditorSceneManager: SceneManager,
mOverlayScene: SceneLayer,
mGameScene: SceneLayer,
mEditorCameraEntity: Entity,

//not editor stuff
mWindow: *Window,
mGameSceneManager: SceneManager,
mFrameAllocator: std.mem.Allocator,

const EditorProgram = @This();

pub fn Init(engine_allocator: std.mem.Allocator, window: *Window, frame_allocator: std.mem.Allocator) !EditorProgram {
    try Renderer.Init(window);
    try ImGui.Init(window);
    return EditorProgram{
        .mGameSceneManager = try SceneManager.Init(window.GetWidth(), window.GetHeight(), engine_allocator),
        .mEditorSceneManager = try SceneManager.Init(window.GetWidth(), window.GetHeight(), engine_allocator),
        .mOverlayScene = undefined,
        .mGameScene = undefined,
        .mEditorCameraEntity = undefined,
        .mWindow = window,
        .mFrameAllocator = frame_allocator,

        ._AssetHandlePanel = AssetHandlePanel.Init(),
        ._ComponentsPanel = ComponentsPanel.Init(),
        ._ContentBrowserPanel = try ContentBrowserPanel.Init(engine_allocator),
        ._CSEditorPanel = CSEditorPanel.Init(engine_allocator),
        ._ScenePanel = ScenePanel.Init(),
        ._ScriptsPanel = ScriptsPanel.Init(),
        ._StatsPanel = StatsPanel.Init(),
        ._ToolbarPanel = try ToolbarPanel.Init(),
        ._ViewportPanel = ViewportPanel.Init(window.GetWidth(), window.GetHeight()),
        ._EditorState = .Stop,
        ._PlayPanel = PlayPanel.Init(),
        ._UsePlayPanel = false,
        ._SceneSpecList = std.ArrayList(SceneSpecPanel).init(engine_allocator),
    };
}

pub fn Setup(self: *EditorProgram) !void {
    self.mOverlayScene = try self.mEditorSceneManager.NewScene(.OverlayLayer);
    self.mGameScene = try self.mEditorSceneManager.NewScene(.GameLayer);

    self.mEditorCameraEntity = try self.mGameScene.CreateEntity();

    const transform_component = self.mEditorCameraEntity.GetComponent(TransformComponent);
    transform_component.SetTranslation(Vec3f32{ 0.0, 0.0, 15.0 });

    var new_camera_component = CameraComponent{};
    new_camera_component.SetViewportSize(self._ViewportPanel.mViewportWidth, self._ViewportPanel.mViewportHeight);
    _ = try self.mEditorCameraEntity.AddComponent(CameraComponent, new_camera_component);

    //TODO: finish the setup for the camera entity
    try GameObjectUtils.AddScriptToEntity(self.mEditorCameraEntity, "assets/scripts/EditorCameraInput.zig", .Eng);
}

pub fn Deinit(self: *EditorProgram) !void {
    try self.mGameSceneManager.Deinit();
    try self.mEditorSceneManager.Deinit();
    self._ContentBrowserPanel.Deinit();

    ImGui.Deinit();
}

//Note other systems to consider in the on update loop
//that isnt there already:
//particles
//handling the loading and unloading of assets and scene transitions
//debug/profiling
pub fn OnUpdate(self: *EditorProgram, dt: f32, frame_allocator: std.mem.Allocator) !void {
    //update asset manager
    try AssetManager.OnUpdate();

    //-------------Inputs Begin------------------
    //Human Inputs
    self.mWindow.PollInputEvents();
    StaticInputContext.OnUpdate();
    try SystemEventManager.ProcessEvents(.EC_Input);
    if (self._EditorState == .Play) {
        _ = try ScriptsProcessor.RunEntityScript(&self.mGameSceneManager, OnUpdateInputScript, .{}, frame_allocator);
    }
    //_ = try ScriptsProcessor.OnUpdateInputEditor(&self._SceneLayer, self._ViewportPanel.mIsFocused);
    _ = try ScriptsProcessor.RunEntityScript(&self.mEditorSceneManager, OnUpdateInputScript, .{}, frame_allocator);

    //AI Inputs

    //-------------Physics Begin-----------------
    //-------------Physics End-------------------

    try self.mGameSceneManager.CalculateTransforms(frame_allocator);
    try self.mEditorSceneManager.CalculateTransforms(frame_allocator);

    //-------------Game Logic Begin--------------
    //-------------Game Logic End----------------

    //-------------Animation Begin--------------
    //-------------Animation End----------------

    //---------Render Begin-------------
    try GameEventManager.ProcessEvents(.EC_PreRender);

    ImGui.Begin();
    Dockspace.Begin();

    try self._ContentBrowserPanel.OnImguiRender();
    try self._AssetHandlePanel.OnImguiRender(frame_allocator);

    try self._ScenePanel.OnImguiRender(&self.mGameSceneManager);
    for (self._SceneSpecList.items) |*scene_spec_panel| {
        try scene_spec_panel.OnImguiRender(frame_allocator);
    }
    try self._ComponentsPanel.OnImguiRender();
    try self._ScriptsPanel.OnImguiRender();
    try self._CSEditorPanel.OnImguiRender();

    try self._ToolbarPanel.OnImguiRender();

    const camera_component = self.mEditorCameraEntity.GetComponent(CameraComponent);
    const camera_transform = self.mEditorCameraEntity.GetComponent(TransformComponent);
    try Renderer.OnUpdate(&self.mGameSceneManager, camera_component, camera_transform);

    try self._ViewportPanel.OnImguiRender(&self.mGameSceneManager.mViewportFrameBuffer, camera_component, camera_transform);

    try self._StatsPanel.OnImguiRender(dt, Renderer.GetRenderStats());

    try Dockspace.OnImguiRender();

    try ImguiEventManager.ProcessEvents();

    Dockspace.End();
    ImGui.End();
    //--------------Render End-------------------

    //--------------Audio Begin------------------
    //--------------Audio End--------------------

    //--------------Networking Begin-------------
    //--------------Networking End---------------

    //-----------------Start End of Frame-----------------
    //swap buffers
    Renderer.SwapBuffers();

    //Process window events
    try SystemEventManager.ProcessEvents(.EC_Window);

    //handle any closed scene spec panels
    self.CleanSceneSpecs();

    //handle deleted objects this frame
    try self.mGameSceneManager.mECSManagerGO.ProcessDestroyedEntities();
    try self.mGameSceneManager.mECSManagerSC.ProcessDestroyedEntities();
    try self.mEditorSceneManager.mECSManagerGO.ProcessDestroyedEntities();
    try self.mEditorSceneManager.mECSManagerSC.ProcessDestroyedEntities();
    try AssetManager.ProcessDestroyedAssets();

    //end of frame resets
    SystemEventManager.EventsReset();
    GameEventManager.EventsReset();
    ImguiEventManager.EventsReset();
    //-----------------End End of Frame-------------------
}

pub fn OnImguiEvent(self: *EditorProgram, event: *ImguiEvent) !void {
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
                .Viewport => self._ViewportPanel.OnTogglePanelEvent(),
                else => @panic("This event has not been handled by this type of panel yet!\n"),
            }
        },
        .ET_NewProjectEvent => |e| {
            if (e.Path.len > 0) {
                try self._ContentBrowserPanel.OnNewProjectEvent(e.Path);
                try AssetManager.OnNewProjectEvent(e.Path);
            }
        },
        .ET_OpenProjectEvent => |e| {
            if (e.Path.len > 0) {
                try self._ContentBrowserPanel.OnOpenProjectEvent(e.Path);
                try AssetManager.OnOpenProjectEvent(e.Path);
            }
        },
        .ET_NewSceneEvent => |e| {
            _ = try self.mGameSceneManager.NewScene(e.mLayerType);
        },
        .ET_SaveSceneEvent => {
            if (self._ScenePanel.mSelectedScene) |scene_layer| {
                try self.mGameSceneManager.SaveScene(scene_layer);
            }
        },
        .ET_SaveSceneAsEvent => |e| {
            if (self._ScenePanel.mSelectedScene) |scene_layer| {
                if (e.Path.len > 0) {
                    const scene_component = scene_layer.GetComponent(SceneComponent);
                    const rel_path = AssetManager.GetRelPath(e.Path);
                    _ = try std.fs.createFileAbsolute(e.Path, .{});
                    scene_component.mSceneAssetHandle = try AssetManager.GetAssetHandleRef(rel_path, .Prj);
                    try self.mGameSceneManager.SaveSceneAs(scene_layer, e.Path);
                }
            }
        },
        .ET_OpenSceneEvent => |e| {
            if (e.Path.len > 0) {
                _ = try self.mGameSceneManager.LoadScene(e.Path);
            }
        },
        .ET_MoveSceneEvent => |e| {
            try self.mGameSceneManager.MoveScene(e.SceneID, e.NewPos);
        },
        .ET_NewEntityEvent => |e| {
            _ = try self.mGameSceneManager.CreateEntity(e.SceneID);
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
            try self.mGameSceneManager.OnViewportResize(e.mWidth, e.mHeight, self.mFrameAllocator);
        },
        .ET_NewScriptEvent => |e| {
            try self._ContentBrowserPanel.OnNewScriptEvent(e);
        },
        .ET_ChangeEditorStateEvent => |e| {
            try self.OnChangeEditorStateEvent(e);
        },
        .ET_OpenSceneSpecEvent => |e| {
            const new_scene_spec_panel = try SceneSpecPanel.Init(e.mSceneLayer);
            try self._SceneSpecList.append(new_scene_spec_panel);
        },
        .ET_SaveEntityEvent => {
            if (self._ScenePanel.mSelectedEntity) |selected_entity| {
                try self.mGameSceneManager.SaveEntity(selected_entity);
            }
        },
        .ET_SaveEntityAsEvent => |e| {
            if (self._ScenePanel.mSelectedEntity) |selected_entity| {
                if (e.Path.len > 0) {
                    try self.mGameSceneManager.SaveEntityAs(selected_entity, e.Path);
                }
            }
        },
        else => std.debug.print("This event has not been handled by editor program!\n", .{}),
    }
}

pub fn OnGameEvent(self: *EditorProgram, event: *GameEvent) !void {
    _ = self;
    switch (event.*) {
        .ET_PrimaryCameraChangeEvent => {},
        else => std.debug.print("This event has not been handled by editor program yet!\n", .{}),
    }
}

pub fn OnChangeEditorStateEvent(self: *EditorProgram, event: ChangeEditorStateEvent) !void {
    if (event.mEditorState == .Play and self._EditorState == .Stop) {
        //TODO:
        //self.mSceneManager.SaveAllScenes();
        //open up a new imgui window which plays the scene from the pov of the primary camera
        self._EditorState = .Play;
        _ = try ScriptsProcessor.RunSceneScript(&self.mGameSceneManager, OnSceneStartScript, .{});
    }
    if (event.mEditorState == .Stop and self._EditorState == .Play) {
        //TODO
        //self.mSceneManager.ReloadAllScenes();
        //close imgui window that plays the scene from the pov of the primary camera
        self._EditorState = .Stop;
    }
}

pub fn OnInputPressedEvent(self: *EditorProgram, e: InputPressedEvent, frame_allocator: std.mem.Allocator) !bool {
    var cont_bool = true;
    if (self._EditorState == .Play) {
        cont_bool = cont_bool and try ScriptsProcessor.RunEntityScript(&self.mGameSceneManager, OnInputPressedScript, .{&e}, frame_allocator);
    }

    cont_bool = cont_bool and self._ViewportPanel.OnInputPressedEvent(e);

    _ = try ScriptsProcessor.RunEntityScript(&self.mEditorSceneManager, OnInputPressedScript, .{&e}, frame_allocator);
    return cont_bool;
}

pub fn OnWindowResize(self: *EditorProgram, width: usize, height: usize, frame_allocator: std.mem.Allocator) !bool {
    try self.mEditorSceneManager.OnViewportResize(width, height, frame_allocator);
    return true;
}

fn CleanSceneSpecs(self: *EditorProgram) void {
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
    self._SceneSpecList.shrinkAndFree(end_index);
}
