const std = @import("std");
const Event = @import("../Events/Event.zig").Event;
const EventManager = @import("../Events/EventManager.zig");
const InputManager = @import("../Inputs/Input.zig");
const ImGui = @import("../Core/Imgui.zig");

const Renderer = @import("../Renderer/Renderer.zig");

//_SceneManager
//_EditorCamera
//_SceneHierarchyPanel
//_ComponentPanel
//_PropertiesPanel
//_ContentBrowserPanel
//_ToolbarPanel

const EditorProgram = @This();
pub fn Init(self: EditorProgram, EngineAllocator: std.mem.Allocator) !void {
    _ = self;
    try Renderer.Init(EngineAllocator);
    ImGui.Init();
    //init imgui
    //init editor camera
    //init each panel
}

pub fn Deinit(self: EditorProgram) void {
    _ = self;
    Renderer.Deinit();
    ImGui.Deinit();
}

pub fn OnUpdate(self: EditorProgram) void {
    _ = self;
    InputManager.PollInputEvents();
    EventManager.ProcessEvents(.EC_Input);
    EventManager.ProcessEvents(.EC_Window);
    EventManager.EventsReset();
    ImGui.Begin();
    ImGui.End();
}

pub fn OnEvent(self: EditorProgram, event: *Event) void {
    _ = self;
    _ = event;
}
