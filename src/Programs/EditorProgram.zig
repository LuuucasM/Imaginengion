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

const EditorProgram = @This();
pub fn Init(self: *EditorProgram, EngineAllocator: std.mem.Allocator) !void {
    self._ScenePanel = try EngineAllocator.create(ScenePanel);
    self._ComponentsPanel = try EngineAllocator.create(ComponentsPanel);
    self._ContentBrowserPanel = try EngineAllocator.create(ContentBrowserPanel);
    self._PropertiesPanel = try EngineAllocator.create(PropertiesPanel);
    self._ScriptsPanel = try EngineAllocator.create(ScriptsPanel);
    self._StatsPanel = try EngineAllocator.create(StatsPanel);
    self._ViewportPanel = try EngineAllocator.create(ViewportPanel);
    try Renderer.Init(EngineAllocator);
    ImGui.Init();
    //init editor camera
    //init each panel
    self._EngineAllocator = EngineAllocator;
}

pub fn Deinit(self: EditorProgram) void {
    self._EngineAllocator.destroy(self._ScenePanel);
    Renderer.Deinit();
    ImGui.Deinit();
}

pub fn OnUpdate(self: EditorProgram, dt: f64) void {
    _ = dt;
    //Process Inputs
    InputManager.PollInputEvents();
    EventManager.ProcessEvents(.EC_Input);

    //Render Imgui
    ImGui.Begin();
    Dockspace.Begin();
    self._ScenePanel.OnImguiRender();
    self._ComponentsPanel.OnImguiRender();
    self._ContentBrowserPanel.OnImguiRender();
    self._PropertiesPanel.OnImguiRender();
    self._ScriptsPanel.OnImguiRender();
    self._StatsPanel.OnImguiRender();
    self._ViewportPanel.OnImguiRender();
    Dockspace.End();
    ImGui.End();

    Renderer.SwapBuffers();

    EventManager.ProcessEvents(.EC_Window);

    EventManager.EventsReset();
}

pub fn OnEvent(self: EditorProgram, event: *Event) void {
    _ = self;
    _ = event;
}
