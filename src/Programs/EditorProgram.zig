const std = @import("std");
const Event = @import("../Events/Event.zig").Event;
const EventManager = @import("../Events/EventManager.zig");
const InputManager = @import("../Inputs/Input.zig");

const ImGui = @import("../Imgui/Imgui.zig");
const Dockspace = @import("../Imgui/Dockspace.zig");
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

const Renderer = @import("../Renderer/Renderer.zig");

//_EditorCamera
_ComponentsPanel: *ComponentsPanel = undefined,
_ContentBrowserPanel: *ContentBrowserPanel = undefined,
_PropertiesPanel: *PropertiesPanel = undefined,
_ScenePanel: *ScenePanel = undefined,
_ScriptsPanel: *ScriptsPanel = undefined,
_StatsPanel: *StatsPanel = undefined,
_ToolbarPanel: *ToolbarPanel = undefined,
_ViewportPanel: *ViewportPanel = undefined,
_EngineAllocator: std.mem.Allocator = undefined,

const EditorProgram = @This();
pub fn Init(self: *EditorProgram, EngineAllocator: std.mem.Allocator) !void {
    try Renderer.Init(EngineAllocator);
    try ImGui.Init(EngineAllocator);
    self._ComponentsPanel = try EngineAllocator.create(ComponentsPanel);
    self._ComponentsPanel.Init();
    self._ContentBrowserPanel = try EngineAllocator.create(ContentBrowserPanel);
    try self._ContentBrowserPanel.Init();
    self._PropertiesPanel = try EngineAllocator.create(PropertiesPanel);
    self._PropertiesPanel.Init();
    self._ScenePanel = try EngineAllocator.create(ScenePanel);
    self._ScenePanel.Init();
    self._ScriptsPanel = try EngineAllocator.create(ScriptsPanel);
    self._ScriptsPanel.Init();
    self._StatsPanel = try EngineAllocator.create(StatsPanel);
    self._StatsPanel.Init();
    self._ToolbarPanel = try EngineAllocator.create(ToolbarPanel);
    self._ToolbarPanel.Init();
    self._ViewportPanel = try EngineAllocator.create(ViewportPanel);
    self._ViewportPanel.Init();
    //init editor camera
    //init each panel
    self._EngineAllocator = EngineAllocator;
}

pub fn Deinit(self: EditorProgram) void {
    self._EngineAllocator.destroy(self._ComponentsPanel);
    self._EngineAllocator.destroy(self._ContentBrowserPanel);
    self._EngineAllocator.destroy(self._PropertiesPanel);
    self._EngineAllocator.destroy(self._ScenePanel);
    self._EngineAllocator.destroy(self._ScriptsPanel);
    self._EngineAllocator.destroy(self._StatsPanel);
    self._EngineAllocator.destroy(self._ToolbarPanel);
    self._EngineAllocator.destroy(self._ViewportPanel);
    ImGui.Deinit();
    Renderer.Deinit();
}

pub fn OnUpdate(self: EditorProgram, dt: f64) !void {
    _ = dt;
    //process asset manager
    try AssetManager.OnUpdate();
    //Process Inputs
    InputManager.PollInputEvents();
    EventManager.ProcessEvents(.EC_Input);

    //Render Imgui
    ImGui.Begin();
    Dockspace.Begin();
    self._ScenePanel.OnImguiRender();
    self._ComponentsPanel.OnImguiRender();
    try self._ContentBrowserPanel.OnImguiRender();
    self._PropertiesPanel.OnImguiRender();
    self._ScriptsPanel.OnImguiRender();
    self._ToolbarPanel.OnImguiRender();
    self._StatsPanel.OnImguiRender();
    self._ViewportPanel.OnImguiRender();
    try Dockspace.OnImguiRender();
    self.ProcessImguiEvents();
    ImGui.ClearEvents();
    Dockspace.End();
    ImGui.End();

    Renderer.SwapBuffers();

    EventManager.ProcessEvents(.EC_Window);

    EventManager.EventsReset();
}

pub fn OnInputEvent(self: EditorProgram, event: *Event) void {
    _ = self;
    _ = event;
}

pub fn OnWindowEvent(self: EditorProgram, event: *Event) void {
    _ = self;
    _ = event;
}

pub fn ProcessImguiEvents(self: EditorProgram) void {
    var it = ImGui.GetFirstEvent();
    while (it) |node| {
        const object_bytes = @as([*]u8, @ptrCast(node)) + @sizeOf(std.SinglyLinkedList(usize).Node);
        const event: *ImguiEvent = @ptrCast(@alignCast(object_bytes));
        switch (event.*) {
            .ET_TogglePanelEvent => |e| {
                switch (e._PanelType) {
                    .Components => self._ComponentsPanel.OnImguiEvent(event),
                    .ContentBrowser => self._ContentBrowserPanel.OnImguiEvent(event),
                    .Properties => self._PropertiesPanel.OnImguiEvent(event),
                    .Scene => self._ScenePanel.OnImguiEvent(event),
                    .Scripts => self._ScriptsPanel.OnImguiEvent(event),
                    .Stats => self._StatsPanel.OnImguiEvent(event),
                    else => std.debug.print("Unexpected panel type!", .{}),
                }
            },
            .ET_NewProjectEvent => {
                AssetManager.UpdateProjectDirectory(event.ET_NewProjectEvent._Path);
                self._ContentBrowserPanel.OnImguiEvent(event);
                self._ComponentsPanel.OnImguiEvent(event);
                self._PropertiesPanel.OnImguiEvent(event);
                self._ScenePanel.OnImguiEvent(event);
                self._ScriptsPanel.OnImguiEvent(event);
            },
        }
        it = node.next;
    }
}
