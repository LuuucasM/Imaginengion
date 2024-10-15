const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const ComponentsPanel = @This();

_P_Open: bool,
//HoveredEntity

pub fn Init() ComponentsPanel {
    return ComponentsPanel{
        ._P_Open = true,
    };
}

pub fn OnImguiRender(self: ComponentsPanel) void {
    if (self._P_Open == false) return;
    _ = imgui.igBegin("Components", null, 0);
    defer imgui.igEnd();
}

pub fn OnImguiEvent(self: *ComponentsPanel, event: *ImguiEvent) void {
    switch (event.*) {
        .ET_TogglePanelEvent => self.OnTogglePanelEvent(),
        else => @panic("Response to that event has not bee implemented yet in ComponentsPanel!\n"),
    }
}

fn OnTogglePanelEvent(self: *ComponentsPanel) void {
    self._P_Open = !self._P_Open;
}