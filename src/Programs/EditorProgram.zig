const Event = @import("../Events/Event.zig").Event;
const EventManager = @import("../Events/EventManager.zig");
const InputManager = @import("../Inputs/Input.zig");

//_SceneManager
//_EditorCamera
//_SceneHierarchyPanel
//_ComponentPanel
//_PropertiesPanel
//_ContentBrowserPanel
//_ToolbarPanel
const EditorProgram = @This();
pub fn Init(self: EditorProgram) void {
    _ = self;
    //init render context
    //note: init for imgui requires glad to be started already
    //init imgui
    //init editor camera
    //init each panel
}

pub fn Deinit(self: EditorProgram) void {
    _ = self;
}

pub fn OnUpdate(self: EditorProgram) void {
    _ = self;
    InputManager.PollInputEvents();
    EventManager.ProcessEvents(.EC_Input);
    EventManager.ProcessEvents(.EC_Window);
    EventManager.EventsReset();
}

pub fn OnEvent(self: EditorProgram, event: *Event) void {
    _ = self;
    _ = event;
}
