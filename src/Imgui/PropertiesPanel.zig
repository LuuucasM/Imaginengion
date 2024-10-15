const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const PropertiesPanel = @This();

_P_Open: bool,
//HoveredEntity

pub fn Init() PropertiesPanel {
    return PropertiesPanel{
        ._P_Open = true,
    };
}

pub fn OnImguiRender(self: PropertiesPanel) void {
    if (self._P_Open == false) return;
    _ = imgui.igBegin("Properties", null, 0);
    defer imgui.igEnd();
}

pub fn OnImguiEvent(self: *PropertiesPanel, event: *ImguiEvent) void {
    switch (event.*) {
        .ET_TogglePanelEvent => self.OnTogglePanelEvent(),
        else => @panic("This event isnt handled yet in PropertiesPanel!\n"),
    }
}

fn OnTogglePanelEvent(self: *PropertiesPanel) void {
    self._P_Open = !self._P_Open;
}