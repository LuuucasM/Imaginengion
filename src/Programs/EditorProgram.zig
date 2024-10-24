const std = @import("std");
const ApplicationManager = @import("../Core/Application.zig");
const Event = @import("../Events/Event.zig").Event;
const EventManager = @import("../Events/EventManager.zig");
const Renderer = @import("../Renderer/Renderer.zig");
const PlatformUtils = @import("../PlatformUtils/PlatformUtils.zig");

const ImGui = @import("../Imgui/Imgui.zig");
const Dockspace = @import("../Imgui/Dockspace.zig");
const AssetHandlePanel = @import("../Imgui/AssethandlePanel.zig");
const ComponentsPanel = @import("../Imgui/ComponentsPanel.zig");
const ContentBrowserPanel = @import("../Imgui/ContentBrowserPanel.zig");
const PropertiesPanel = @import("../Imgui/PropertiesPanel.zig");
const ScenePanel = @import("../Imgui/ScenePanel.zig");
const ScriptsPanel = @import("../Imgui/ScriptsPanel.zig");
const StatsPanel = @import("../Imgui/StatsPanel.zig");
const ToolbarPanel = @import("../Imgui/ToolbarPanel.zig");
const ViewportPanel = @import("../Imgui/ViewportPanel.zig");
const ImguiEvent = @import("../Imgui/ImguiEvent.zig").ImguiEvent;
const AssetManager = @import("../Assets/AssetManager.zig");
const EditorSceneManager = @import("../Scene/SceneManager.zig");

_AssetHandlePanel: AssetHandlePanel,
_ComponentsPanel: ComponentsPanel,
_ContentBrowserPanel: ContentBrowserPanel,
_PropertiesPanel: PropertiesPanel,
_ScenePanel: ScenePanel,
_ScriptsPanel: ScriptsPanel,
_StatsPanel: StatsPanel,
_ToolbarPanel: ToolbarPanel,
_ViewportPanel: ViewportPanel,
mSceneManager: EditorSceneManager,
//_EditorCamera

const EditorProgram = @This();

pub fn Init(EngineAllocator: std.mem.Allocator) !EditorProgram {
    try ImGui.Init(EngineAllocator);

    return EditorProgram{
        .mSceneManager = try EditorSceneManager.Init(1600, 900),
        ._AssetHandlePanel = AssetHandlePanel.Init(),
        ._ComponentsPanel = ComponentsPanel.Init(),
        ._ContentBrowserPanel = try ContentBrowserPanel.Init(),
        ._PropertiesPanel = PropertiesPanel.Init(),
        ._ScenePanel = ScenePanel.Init(),
        ._ScriptsPanel = ScriptsPanel.Init(),
        ._StatsPanel = StatsPanel.Init(),
        ._ToolbarPanel = ToolbarPanel.Init(),
        ._ViewportPanel = ViewportPanel.Init(),
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
    ApplicationManager.GetWindow().PollInputEvents();
    EventManager.ProcessEvents(.EC_Input);
    //---------Inputs End----------------

    //---------Physics Begin-------------
    //---------Physics End---------------

    //---------Game Logic Begin----------
    //---------GameLogic End-------------

    //---------Render Begin-------------
    //Imgui begin
    ImGui.Begin();
    Dockspace.Begin();

    try self._AssetHandlePanel.OnImguiRender();
    try self._ScenePanel.OnImguiRender(&self.mSceneManager.mSceneStack);
    try self._ContentBrowserPanel.OnImguiRender();
    self._ComponentsPanel.OnImguiRender();
    self._PropertiesPanel.OnImguiRender();
    self._ScriptsPanel.OnImguiRender();
    self._ToolbarPanel.OnImguiRender();
    try self._StatsPanel.OnImguiRender(dt);
    self._ViewportPanel.OnImguiRender();
    try Dockspace.OnImguiRender();

    try self.ProcessImguiEvents();
    ImGui.ClearEvents();

    Dockspace.End();
    ImGui.End();
    //Imgui end

    Renderer.SwapBuffers();
    //----------Render End-----------------

    //----------Audio Begin----------------
    //----------Audio End------------------

    //----------Networking Begin-----------
    //----------Networking End-------------

    //Finally Process window events
    EventManager.ProcessEvents(.EC_Window);

    //end of frame resets
    EventManager.EventsReset();
}

pub fn OnEvent(self: EditorProgram, event: *Event) void {
    _ = self;
    _ = event;
}

pub fn ProcessImguiEvents(self: *EditorProgram) !void {
    var it = ImGui.GetFirstEvent();
    while (it) |node| {
        const object_bytes = @as([*]u8, @ptrCast(node)) + @sizeOf(std.SinglyLinkedList(usize).Node);
        const event: *ImguiEvent = @ptrCast(@alignCast(object_bytes));
        switch (event.*) {
            .ET_TogglePanelEvent => |e| {
                switch (e._PanelType) {
                    .AssetHandles => self._AssetHandlePanel.OnTogglePanelEvent(),
                    .Components => self._ComponentsPanel.OnTogglePanelEvent(),
                    .ContentBrowser => self._ContentBrowserPanel.OnTogglePanelEvent(),
                    .Properties => self._PropertiesPanel.OnTogglePanelEvent(),
                    .Scene => self._ScenePanel.OnTogglePanelEvent(),
                    .Scripts => self._ScriptsPanel.OnTogglePanelEvent(),
                    .Stats => self._StatsPanel.OnTogglePanelEvent(),
                    else => @panic("This event has not been handled by this type of panel yet!\n"),
                }
            },
            .ET_NewProjectEvent => {
                var buffer: [260]u8 = undefined;
                var fba = std.heap.FixedBufferAllocator.init(&buffer);
                const path = try PlatformUtils.OpenFolder(fba.allocator());
                if (path.len > 0){
                    try AssetManager.UpdateProjectDirectory(path);
                    try self._ContentBrowserPanel.OnNewProjectEvent(path);
                }
            },
            .ET_OpenProjectEvent => {
                var buffer: [260]u8 = undefined;
                var fba = std.heap.FixedBufferAllocator.init(&buffer);
                const path = try PlatformUtils.OpenFile(fba.allocator(), ".imprj");
                if (path.len > 0){
                    try AssetManager.UpdateProjectDirectory(std.fs.path.dirname(path).?);
                    try self._ContentBrowserPanel.OnOpenProjectEvent(path);
                }
            },
            .ET_NewSceneEvent => |e| {
                _ = try self.mSceneManager.NewScene(e.mLayerType);
            },
            .ET_SaveSceneEvent => {
                //get the save path
                //get the currently selected scene from the scene manager.
                //if that scene has a path, call scenemanager.savescene(path)
                //if it does not have a path call scenemanager.savesceneas(path) instead
            },
            .ET_SaveSceneAsEvent => {
                //get the save path
                //call scenemanager.savesceneas(path)
            },
            .ET_OpenSceneEvent => {
                var buffer: [260]u8 = undefined;
                var fba = std.heap.FixedBufferAllocator.init(&buffer);
                const path = try PlatformUtils.OpenFile(fba.allocator(), ".imsc");
                if (path.len > 0){
                    _ = try self.mSceneManager.LoadScene(path);    
                }
            },
            else => std.debug.print("This event has not been handled by editor program!\n", .{}),
        }
        it = node.next;
    }
}
