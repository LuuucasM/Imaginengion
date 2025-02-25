const std = @import("std");
const Window = @import("../Windows/Window.zig");
const Renderer = @import("../Renderer/Renderer.zig");

const LinAlg = @import("../Math/LinAlg.zig");
const Components = @import("../GameObjects/Components.zig");
const CameraComponent = Components.CameraComponent;
const TransformComponent = Components.TransformComponent;

const SystemEvent = @import("../Events/SystemEvent.zig").SystemEvent;
const KeyPressedEvent = @import("../Events/SystemEvent.zig").KeyPressedEvent;
const SystemEventManager = @import("../Events/SystemEventManager.zig");
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const ImguiEventManager = @import("../Events/ImguiEventManager.zig");
const GameEvent = @import("../Events/GameEvent.zig").GameEvent;
const GameEventManager = @import("../Events/GameEventManager.zig");

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
const AssetManager = @import("../Assets/AssetManager.zig");
const EditorSceneManager = @import("../Scene/SceneManager.zig");
//const ScriptManager = @import("../Scripts/ScriptManager.zig");

_AssetHandlePanel: AssetHandlePanel,
_ComponentsPanel: ComponentsPanel,
_ContentBrowserPanel: ContentBrowserPanel,
_CSEditorPanel: CSEditorPanel,
_ScenePanel: ScenePanel,
_ScriptsPanel: ScriptsPanel,
_StatsPanel: StatsPanel,
_ToolbarPanel: ToolbarPanel,
_ViewportPanel: ViewportPanel,
mSceneManager: EditorSceneManager,
mWindow: *Window,
//mScriptManager: ScriptManager,

const EditorProgram = @This();

pub fn Init(engine_allocator: std.mem.Allocator, window: *Window) !EditorProgram {
    try ImGui.Init(window);

    return EditorProgram{
        .mSceneManager = try EditorSceneManager.Init(1600, 900),
        .mWindow = window,
        ._AssetHandlePanel = AssetHandlePanel.Init(),
        ._ComponentsPanel = ComponentsPanel.Init(),
        ._ContentBrowserPanel = try ContentBrowserPanel.Init(engine_allocator),
        ._CSEditorPanel = CSEditorPanel.Init(engine_allocator),
        ._ScenePanel = ScenePanel.Init(),
        ._ScriptsPanel = ScriptsPanel.Init(),
        ._StatsPanel = StatsPanel.Init(),
        ._ToolbarPanel = try ToolbarPanel.Init(),
        ._ViewportPanel = ViewportPanel.Init(),
        //.mScriptManager = ScriptManager.Init(engine_allocator),
    };
}

pub fn Deinit(self: *EditorProgram) !void {
    self._ContentBrowserPanel.Deinit();
    try self.mSceneManager.Deinit();
    ImGui.Deinit();
}

pub fn OnUpdate(self: *EditorProgram, dt: f64) !void {
    //update asset manager
    try AssetManager.OnUpdate();

    //---------Inputs Begin--------------
    self.mWindow.PollInputEvents();
    SystemEventManager.ProcessEvents(.EC_Input);
    //---------Inputs End----------------

    //---------Physics Begin-------------
    //---------Physics End---------------

    //---------Game Logic Begin----------
    //---------Game Logic End-------------

    //---------Render Begin-------------
    try GameEventManager.ProcessEvents(.EC_PreRender);
    try self.mSceneManager.RenderUpdate();

    Renderer.SwapBuffers();
    //----------Render End-----------------

    //----------Audio Begin----------------
    //----------Audio End------------------

    //----------Networking Begin-----------
    //----------Networking End-------------

    //----------Imgui begin----------------
    ImGui.Begin();
    Dockspace.Begin();
    try self._ContentBrowserPanel.OnImguiRender();
    try self._AssetHandlePanel.OnImguiRender();

    try self._ScenePanel.OnImguiRender(&self.mSceneManager.mSceneStack);

    try self._ComponentsPanel.OnImguiRender();
    self._ScriptsPanel.OnImguiRender();
    try self._CSEditorPanel.OnImguiRender();

    try self._ToolbarPanel.OnImguiRender();
    const camera_component = self.mSceneManager.mECSManager.GetComponent(CameraComponent, self.mSceneManager.mEditorCameraEntityID);
    const camera_transform = self.mSceneManager.mECSManager.GetComponent(TransformComponent, self.mSceneManager.mEditorCameraEntityID);
    const camera_view_projection = LinAlg.Mat4MulMat4(camera_component.mProjection, LinAlg.Mat4Inverse(camera_transform.GetTransformMatrix()));
    try self._ViewportPanel.OnImguiRender(&self.mSceneManager.mFrameBuffer, camera_component.mProjectionType, camera_component.mProjection, camera_view_projection);

    try self._StatsPanel.OnImguiRender(dt, Renderer.GetRenderStats());

    try Dockspace.OnImguiRender();

    try ImguiEventManager.ProcessEvents();

    Dockspace.End();
    ImGui.End();
    //----------Imgui end------------------

    //Process window events
    SystemEventManager.ProcessEvents(.EC_Window);

    //handle deleted objects this frame
    self.mSceneManager.mECSManager.ProcessDestroyedEntities();

    //end of frame resets
    SystemEventManager.EventsReset();
    GameEventManager.EventsReset();
    ImguiEventManager.EventsReset();
}

pub fn OnKeyPressedEvent(self: *EditorProgram, e: KeyPressedEvent) bool {
    if (self._ViewportPanel.OnKeyPressedEvent(e) == true) {
        return true;
    }
    return false;
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
            }
        },
        .ET_OpenProjectEvent => |e| {
            if (e.Path.len > 0) {
                try self._ContentBrowserPanel.OnOpenProjectEvent(e.Path);
            }
        },
        .ET_NewSceneEvent => |e| {
            _ = try self.mSceneManager.NewScene(e.mLayerType);
        },
        .ET_SaveSceneEvent => {
            if (self._ScenePanel.mSelectedScene) |scene_id| {
                try self.mSceneManager.SaveScene(scene_id);
            }
        },
        .ET_SaveSceneAsEvent => |e| {
            if (self._ScenePanel.mSelectedScene) |scene_id| {
                if (e.Path.len > 0) {
                    try self.mSceneManager.SaveSceneAs(scene_id, e.Path);
                }
            }
        },
        .ET_OpenSceneEvent => |e| {
            if (e.Path.len > 0) {
                _ = try self.mSceneManager.LoadScene(e.Path);
            }
        },
        .ET_MoveSceneEvent => |e| {
            self.mSceneManager.MoveScene(e.SceneID, e.NewPos);
        },
        .ET_NewEntityEvent => |e| {
            _ = try self.mSceneManager.CreateEntity(e.SceneID);
        },
        .ET_SelectSceneEvent => |e| {
            self._ScenePanel.OnSelectSceneEvent(e.SelectedScene);
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
            try self.mSceneManager.OnViewportResize(e.mWidth, e.mHeight);
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
