const std = @import("std");
const Event = @import("../Events/Event.zig").Event;
const EventManager = @import("../Events/EventManager.zig");
const InputManager = @import("../Inputs/Input.zig");

const ImGui = @import("../Imgui/Imgui.zig");
const Dockspace = @import("../Imgui/Dockspace.zig");
const ScenePanel = @import("../Imgui/ScenePanel.zig");
const ViewportPanel = @import("../Imgui/ViewportPanel.zig");
const ComponentsPanel = @import("../Imgui/ComponentsPanel.zig");
const ContentBrowserPanel = @import("../Imgui/ContentBrowserPanel.zig");
const PropertiesPanel = @import("../Imgui/PropertiesPanel.zig");
const ScriptsPanel = @import("../Imgui/ScriptsPanel.zig");
const StatsPanel = @import("../Imgui/StatsPanel.zig");
const ImguiEvent = @import("../Imgui/ImguiEvent.zig").ImguiEvent;

const Renderer = @import("../Renderer/Renderer.zig");

_ViewportPanel: *ViewportPanel = undefined,
//_EditorCamera
_ScenePanel: *ScenePanel = undefined,
_ComponentsPanel: *ComponentsPanel = undefined,
_PropertiesPanel: *PropertiesPanel = undefined,
_ContentBrowserPanel: *ContentBrowserPanel = undefined,
_ScriptsPanel: *ScriptsPanel = undefined,
_StatsPanel: *StatsPanel = undefined,
_EngineAllocator: std.mem.Allocator = undefined,
//_Dockspace: *Dockspace = undefined,

const EditorProgram = @This();
pub fn Init(self: *EditorProgram, EngineAllocator: std.mem.Allocator) !void {
    self._ScenePanel = try EngineAllocator.create(ScenePanel);
    self._ComponentsPanel = try EngineAllocator.create(ComponentsPanel);
    self._ContentBrowserPanel = try EngineAllocator.create(ContentBrowserPanel);
    self._PropertiesPanel = try EngineAllocator.create(PropertiesPanel);
    self._ScriptsPanel = try EngineAllocator.create(ScriptsPanel);
    self._StatsPanel = try EngineAllocator.create(StatsPanel);
    self._ViewportPanel = try EngineAllocator.create(ViewportPanel);
    self._ScenePanel.Init();
    try Renderer.Init(EngineAllocator);
    try ImGui.Init(EngineAllocator);
    //init editor camera
    //init each panel
    self._EngineAllocator = EngineAllocator;
}

pub fn Deinit(self: EditorProgram) void {
    self._EngineAllocator.destroy(self._ScenePanel);
    self._EngineAllocator.destroy(self._ComponentsPanel);
    self._EngineAllocator.destroy(self._ContentBrowserPanel);
    self._EngineAllocator.destroy(self._PropertiesPanel);
    self._EngineAllocator.destroy(self._ScriptsPanel);
    self._EngineAllocator.destroy(self._StatsPanel);
    self._EngineAllocator.destroy(self._ViewportPanel);
    ImGui.Deinit();
    Renderer.Deinit();
    self._EngineAllocator.destroy(self._ScenePanel);
}

pub fn OnUpdate(self: EditorProgram, dt: f64) !void {
    _ = dt;
    //Process Inputs
    InputManager.PollInputEvents();
    EventManager.ProcessEvents(.EC_Input);

    //Render Imgui
    ImGui.Begin();
    Dockspace.Begin();
    try Dockspace.OnImguiRender();
    self._ScenePanel.OnImguiRender();
    self._ComponentsPanel.OnImguiRender();
    self._ContentBrowserPanel.OnImguiRender();
    self._PropertiesPanel.OnImguiRender();
    self._ScriptsPanel.OnImguiRender();
    self._StatsPanel.OnImguiRender();
    self._ViewportPanel.OnImguiRender(); //note: for the editor, game rendering is done in here
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

        if (event.GetPanelType() == .Scene) {
            self._ScenePanel.OnImguiEvent(event);
        } else {
            @panic("This panel doesnt support events yet");
        }

        it = node.next;
    }
}
