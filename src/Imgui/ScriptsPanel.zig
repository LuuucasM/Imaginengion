const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const ScriptsPanel = @This();

_P_Open: bool = true,
//HoveredEntity

pub fn Init(self: *ScriptsPanel) void {
    self._P_Open = true;
}

pub fn OnImguiRender(self: ScriptsPanel) void {
    if (self._P_Open == false) return;
    _ = imgui.igBegin("Scripts", null, 0);
    defer imgui.igEnd();
}

pub fn OnImguiEvent(self: *ScriptsPanel, event: *ImguiEvent) void {
    switch (event.*) {
        .ET_TogglePanelEvent => self._P_Open = !self._P_Open,
        else => @panic("This event isnt haneled yet in ScriptsPanel\n"),
    }
}
