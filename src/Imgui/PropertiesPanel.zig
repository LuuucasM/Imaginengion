const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const PropertiesPanel = @This();

mP_Open: bool,

pub fn Init() PropertiesPanel {
    return PropertiesPanel{
        .mP_Open = true,
    };
}

pub fn OnImguiRender(self: PropertiesPanel, selected_entity_ref: ?*Entity) void {
    if (self.mP_Open == false) return;
    _ = imgui.igBegin("Properties", null, 0);
    defer imgui.igEnd();

    if (selected_entity_ref) |entity|{
        selected_entity_ref.OnImguiRender();
    }
}

pub fn OnImguiEvent(self: *PropertiesPanel, event: *ImguiEvent) void {
    switch (event.*) {
        .ET_TogglePanelEvent => self.OnTogglePanelEvent(),
        else => @panic("This event isnt handled yet in PropertiesPanel!\n"),
    }
}

pub fn OnTogglePanelEvent(self: *PropertiesPanel) void {
    self.mP_Open = !self.mP_Open;
}