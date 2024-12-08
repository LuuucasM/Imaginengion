const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const Entity = @import("../ECS/Entity.zig");
const ScriptsPanel = @This();

_P_Open: bool,
//HoveredEntity

pub fn Init() ScriptsPanel {
    return ScriptsPanel{
        ._P_Open = true,
    };
}

pub fn OnImguiRender(self: ScriptsPanel, selected_entity_ref: ?Entity) void {
    if (self._P_Open == false) return;
    _ = imgui.igBegin("Scripts", null, 0);
    defer imgui.igEnd();

    if (selected_entity_ref) |entity| {
        _ = entity;
        //entity.ScriptsImguiRender();
    }
}

pub fn OnImguiEvent(self: *ScriptsPanel, event: *ImguiEvent) void {
    switch (event.*) {
        .ET_TogglePanelEvent => self.OnTogglePanelEvent(),
        else => @panic("This event isnt haneled yet in ScriptsPanel\n"),
    }
}

pub fn OnTogglePanelEvent(self: *ScriptsPanel) void {
    self._P_Open = !self._P_Open;
}
