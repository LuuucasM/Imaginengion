const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const Entity = @import("../ECS/Entity.zig");
const EditorWindow = @import("EditorWindow.zig");
const CSEditorPanel = @This();

mP_Open: bool,
mEditorWindows: std.ArrayList(EditorWindow),
const EditorWindowsGPA = std.heap.GeneralPurposeAllocator(.{}){};

pub fn Init() CSEditorPanel {
    return CSEditorPanel{
        .mP_Open = true,
        .mEditorWindows = std.ArrayList(EditorWindow).init(EditorWindowsGPA.allocator()),
    };
}

pub fn OnImguiRender(self: CSEditorPanel) void {
    if (self.mP_Open == false) return;
    _ = imgui.igBegin("Component/Scripts Editor", null, 0);
    for (self.mEditorWIndows.list) |window| {
        _ = imgui.igBegin("", null, 0);
        window.ImguiRender();
    }
    defer imgui.igEnd();
}

pub fn OnImguiEvent(self: *CSEditorPanel, event: *ImguiEvent) void {
    switch (event.*) {
        .ET_TogglePanelEvent => self.OnTogglePanelEvent(),
        else => @panic("This event isnt handled yet in Component/Scripts Editor Panel!\n"),
    }
}

pub fn OnTogglePanelEvent(self: *CSEditorPanel) void {
    self.mP_Open = !self.mP_Open;
}
