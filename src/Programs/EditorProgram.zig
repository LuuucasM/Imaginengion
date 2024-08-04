const std = @import("std");
const Event = @import("../Events/Event.zig").Event;
const EventManager = @import("../Events/EventManager.zig");
const InputManager = @import("../Inputs/Input.zig");

const ImGui = @import("../Imgui/Imgui.zig");
const Dockspace = @import("../Imgui/Dockspace.zig");

const Renderer = @import("../Renderer/Renderer.zig");

//_ViewportPanel
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
    //Process Inputs
    InputManager.PollInputEvents();
    EventManager.ProcessEvents(.EC_Input);

    //Render Scene
    //TODO

    //Render Imgui
    ImGui.Begin();
    Dockspace.Begin();
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
