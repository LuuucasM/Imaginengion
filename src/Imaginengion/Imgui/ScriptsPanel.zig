const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const Entity = @import("../GameObjects/Entity.zig");
const ScriptsPanel = @This();

_P_Open: bool,
mSelectedEntity: ?Entity,

pub fn Init() ScriptsPanel {
    return ScriptsPanel{
        ._P_Open = true,
        .mSelectedEntity = null,
    };
}

pub fn OnImguiRender(self: ScriptsPanel) void {
    if (self._P_Open == false) return;
    _ = imgui.igBegin("Scripts", null, 0);
    defer imgui.igEnd();

    if (self.mSelectedEntity) |entity| {
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

pub fn OnSelectEntityEvent(self: *ScriptsPanel, new_selected_entity: ?Entity) void {
    self.mSelectedEntity = new_selected_entity;
}
