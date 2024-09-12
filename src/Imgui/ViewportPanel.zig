const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const ViewportPanel = @This();

_P_Open: bool = true,

pub fn Init(self: *ViewportPanel) void {
    self._P_Open = true;
}

pub fn OnImguiRender(self: ViewportPanel) void {
    if (self._P_Open == false) return;
    _ = imgui.igBegin("Viewport", null, 0);
    defer imgui.igEnd();
}

pub fn OnImguiEvent(self: *ViewportPanel, event: *ImguiEvent) void {
    switch (event.*) {
        .ET_TogglePanelEvent => self.OnTogglePanelEvent(),
        else => @panic("This event has not been handled yet in ViewportPanel!\n"),
    }
}

fn OnTogglePanelEvent(self: *ViewportPanel) void {
    self._P_Open = !self._P_Open;
}