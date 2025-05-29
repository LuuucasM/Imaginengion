const std = @import("std");

const Window = @import("../Windows/Window.zig");
const Renderer = @import("../Renderer/Renderer.zig");
const StaticInputContext = @import("../Inputs/Input.zig");
const ScriptsProcessor = @import("../Scripts/ScriptsProcessor.zig");

const LinAlg = @import("../Math/LinAlg.zig");

const EntityComponents = @import("../GameObjects/Components.zig");
const CameraComponent = EntityComponents.CameraComponent;
const TransformComponent = EntityComponents.TransformComponent;
const EditorCameraTag = EntityComponents.EditorCameraTag;
const PrimaryCameraTag = EntityComponents.PrimaryCameraTag;
const SceneComponents = @import("../Scene/SceneComponents.zig");
const SceneComponent = SceneComponents.SceneComponent;

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

const EditorSceneManager = @import("../Scene/SceneManager.zig");
const SceneLayer = @import("../Scene/SceneLayer.zig");
const EditorState = @import("../Imgui/ToolbarPanel.zig").EditorState;
const FrameBuffer = @import("../FrameBuffers/FrameBuffer.zig");
const TextureFormat = @import("../FrameBuffers/InternalFrameBuffer.zig").TextureFormat;

const OnInputPressedScript = @import("../GameObjects/Components.zig").OnInputPressedScript;
const OnUpdateInputScript = @import("../GameObjects/Components.zig").OnUpdateInputScript;

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
mSceneManager: EditorSceneManager,
_SceneLayer: SceneLayer,
mWindow: *Window,
_EditorState: EditorState,
_UsePlayPanel: bool,
_SceneSpecList: std.ArrayList(SceneSpecPanel),

const EditorProgram = @This();

pub fn Init(engine_allocator: std.mem.Allocator, window: *Window) !EditorProgram {
    try ImGui.Init(window);
    return EditorProgram{
        .mSceneManager = try EditorSceneManager.Init(window.GetWidth(), window.GetHeight()),
        .mWindow = window,
        ._AssetHandlePanel = AssetHandlePanel.Init(),
        ._ComponentsPanel = ComponentsPanel.Init(),
        ._ContentBrowserPanel = try ContentBrowserPanel.Init(engine_allocator),
        ._CSEditorPanel = CSEditorPanel.Init(engine_allocator),
        ._ScenePanel = ScenePanel.Init(),
        ._ScriptsPanel = ScriptsPanel.Init(),
        ._StatsPanel = StatsPanel.Init(),
        ._ToolbarPanel = try ToolbarPanel.Init(),
        ._ViewportPanel = undefined,
        ._SceneLayer = undefined,
        ._EditorState = .Stop,
        ._PlayPanel = PlayPanel.Init(),
        ._UsePlayPanel = false,
        ._SceneSpecList = std.ArrayList(SceneSpecPanel).init(engine_allocator),
    };
}

pub fn Setup(self: *EditorProgram) !void {
    self._SceneLayer = SceneLayer{ .mSceneID = try self.mSceneManager.mECSManagerSC.CreateEntity(), .mECSManagerGORef = &self.mSceneManager.mECSManagerGO, .mECSManagerSCRef = &self.mSceneManager.mECSManagerSC };
    _ = try self._SceneLayer.AddComponent(SceneComponent, SceneComponent{
        .mLayerType = .GameLayer,
        .mFrameBuffer = try FrameBuffer.Init(EditorSceneManager.SceneManagerGPA.allocator(), &[_]TextureFormat{.RGBA8}, .DEPTH24STENCIL8, 1, false, self.mWindow.GetWidth(), self.mWindow.GetHeight()),
    });

    self._ViewportPanel = try ViewportPanel.Init(&self._SceneLayer, self.mWindow.GetHeight(), self.mWindow.GetWidth());
}

pub fn Deinit(self: *EditorProgram) !void {
    self._ContentBrowserPanel.Deinit();
    try self.mSceneManager.Deinit();
    ImGui.Deinit();
}

//Note other systems to consider in the on update loop
//that isnt there already:
//particles
//handling the loading and unloading of assets and scene transitions
//debug/profiling
pub fn OnUpdate(self: *EditorProgram, dt: f32) !void {
    //update asset manager
    try AssetManager.OnUpdate();

    //-------------Inputs Begin------------------
    self.mWindow.PollInputEvents();
    StaticInputContext.OnUpdate();
    try SystemEventManager.ProcessEvents(.EC_Input);
    if (self._EditorState == .Play) {
        _ = try ScriptsProcessor.RunScript(&self.mSceneManager, OnUpdateInputScript, .{});
    }
    //_ = try ScriptsProcessor.OnUpdateInputEditor(&self._SceneLayer, self._ViewportPanel.mIsFocused);
    _ = try ScriptsProcessor.RunScriptEditor(&self._SceneLayer, self._ViewportPanel.mIsFocused, OnUpdateInputScript, .{});
    //-------------Inputs End--------------------

    //-------------AI Begin--------------
    //-------------AI End----------------

    //-------------Physics Begin-----------------
    //-------------Physics End-------------------

    //-------------Game Logic Begin--------------
    //-------------Game Logic End----------------

    //-------------Animation Begin--------------
    //-------------Animation End----------------

    //---------Render Begin-------------
    try GameEventManager.ProcessEvents(.EC_PreRender);

    ImGui.Begin();
    Dockspace.Begin();
    try self._ContentBrowserPanel.OnImguiRender();
    try self._AssetHandlePanel.OnImguiRender();

    try self._ScenePanel.OnImguiRender(&self.mSceneManager);
    for (self._SceneSpecList.items) |scene_spec_panel| {
        scene_spec_panel.OnImguiRender();
    }

    try self._ComponentsPanel.OnImguiRender();
    try self._ScriptsPanel.OnImguiRender();
    try self._CSEditorPanel.OnImguiRender();

    try self._ToolbarPanel.OnImguiRender();

    var buffer: [300]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    if (self._UsePlayPanel == true) {
        const editor_camera_group = try self.mSceneManager.mECSManagerGO.GetGroup(.{ .Component = EditorCameraTag }, allocator);
        const camera_component = self.mSceneManager.mECSManagerGO.GetComponent(CameraComponent, editor_camera_group.items[0]);
        const camera_transform = self.mSceneManager.mECSManagerGO.GetComponent(TransformComponent, editor_camera_group.items[0]);
        try Renderer.OnUpdate(&self.mSceneManager, camera_component, camera_transform);
        try self._ViewportPanel.OnImguiRender(&self.mSceneManager.mFrameBuffer, camera_component, camera_transform);

        if (self._EditorState == .Play) {
            const primary_camera_group = try self.mSceneManager.mECSManagerGO.GetGroup(.{ .Component = PrimaryCameraTag }, allocator);
            if (primary_camera_group.items.len > 0) {
                const play_camera_component = self.mSceneManager.mECSManagerGO.GetComponent(CameraComponent, primary_camera_group.items[0]);
                const play_camera_transform = self.mSceneManager.mECSManagerGO.GetComponent(TransformComponent, primary_camera_group.items[0]);
                try Renderer.OnUpdate(&self.mSceneManager, play_camera_component, play_camera_transform);
                try self._PlayPanel.OnImguiRender(&self.mSceneManager.mFrameBuffer);
            }
        }
    } else {
        if (self._EditorState == .Play) {
            const primary_camera_group = try self.mSceneManager.mECSManagerGO.GetGroup(.{ .Component = PrimaryCameraTag }, allocator);
            if (primary_camera_group.items.len > 0) {
                const camera_component = self.mSceneManager.mECSManagerGO.GetComponent(CameraComponent, primary_camera_group.items[0]);
                const camera_transform = self.mSceneManager.mECSManagerGO.GetComponent(TransformComponent, primary_camera_group.items[0]);
                try Renderer.OnUpdate(&self.mSceneManager, camera_component, camera_transform);
                try self._ViewportPanel.OnImguiRenderPlay(&self.mSceneManager.mFrameBuffer);
            }
        } else {
            const editor_camera_group = try self.mSceneManager.mECSManagerGO.GetGroup(.{ .Component = EditorCameraTag }, allocator);
            const camera_component = self.mSceneManager.mECSManagerGO.GetComponent(CameraComponent, editor_camera_group.items[0]);
            const camera_transform = self.mSceneManager.mECSManagerGO.GetComponent(TransformComponent, editor_camera_group.items[0]);
            try Renderer.OnUpdate(&self.mSceneManager, camera_component, camera_transform);
            try self._ViewportPanel.OnImguiRender(&self.mSceneManager.mFrameBuffer, camera_component, camera_transform);
        }
    }

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
    try self.mSceneManager.mECSManagerGO.ProcessDestroyedEntities();
    try self.mSceneManager.mECSManagerSC.ProcessDestroyedEntities();
    try AssetManager.ProcessDestroyedAssets();

    //end of frame resets
    SystemEventManager.EventsReset();
    GameEventManager.EventsReset();
    ImguiEventManager.EventsReset();
    //-----------------End End of Frame-------------------
}

pub fn OnWindowResize(self: *EditorProgram, width: usize, height: usize) !bool {
    const editor_scene_component = self._SceneLayer.GetComponent(SceneComponent);
    editor_scene_component.mFrameBuffer.Resize(width, height);

    _ = try self._ViewportPanel.OnWindowResize(width, height);
    return true;
}

pub fn OnInputPressedEvent(self: *EditorProgram, e: InputPressedEvent) !bool {
    var cont_bool = true;
    if (self._EditorState == .Play) {
        cont_bool = cont_bool and try ScriptsProcessor.RunScript(&self.mSceneManager, OnInputPressedScript, .{&e});
    }

    cont_bool = cont_bool and self._ViewportPanel.OnInputPressedEvent(e);

    _ = try ScriptsProcessor.RunScriptEditor(&self._SceneLayer, self._ViewportPanel.mIsFocused, OnInputPressedScript, .{&e});
    return cont_bool;
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
            _ = try self.mSceneManager.NewScene(e.mLayerType);
        },
        .ET_SaveSceneEvent => {
            if (self._ScenePanel.mSelectedScene) |scene_layer| {
                try self.mSceneManager.SaveScene(scene_layer.mSceneID);
            }
        },
        .ET_SaveSceneAsEvent => |e| {
            if (self._ScenePanel.mSelectedScene) |scene_layer| {
                if (e.Path.len > 0) {
                    try self.mSceneManager.SaveSceneAs(scene_layer.mSceneID, e.Path);
                }
            }
        },
        .ET_OpenSceneEvent => |e| {
            if (e.Path.len > 0) {
                _ = try self.mSceneManager.LoadScene(e.Path);
            }
        },
        .ET_MoveSceneEvent => |e| {
            try self.mSceneManager.MoveScene(e.SceneID, e.NewPos);
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
        .ET_NewScriptEvent => |e| {
            try self._ContentBrowserPanel.OnNewScriptEvent(e);
        },
        .ET_ChangeEditorStateEvent => |e| {
            self.OnChangeEditorStateEvent(e);
        },
        .ET_OpenSceneSpecEvent => |e| {
            const new_scene_spec_panel = try SceneSpecPanel.Init(e.mSceneLayer);
            try self._SceneSpecList.append(new_scene_spec_panel);
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

pub fn OnChangeEditorStateEvent(self: *EditorProgram, event: ChangeEditorStateEvent) void {
    if (event.mEditorState == .Play and self._EditorState == .Stop) {
        //TODO:
        //self.mSceneManager.SaveAllScenes();
        //open up a new imgui window which plays the scene from the pov of the primary camera
        //self._EditorState = .Play;
    }
    if (event.mEditorState == .Stop and self._EditorState == .Play) {
        //TODO
        //self.mSceneManager.ReloadAllScenes();
        //close imgui window that plays the scene from the pov of the primary camera
        //self._EditorState = .Stop;
    }
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
