const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const Entity = @import("../ECS/Entity.zig");
const ComponentsPanel = @This();

_P_Open: bool,
mSelectedEntity: ?Entity,

pub fn Init() ComponentsPanel {
    return ComponentsPanel{
        ._P_Open = true,
        .mSelectedEntity = null,
    };
}

pub fn OnImguiRender(self: ComponentsPanel) !void {
    if (self._P_Open == false) return;

    if (self.mSelectedEntity) |entity| {
        var buffer: [300]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        const name = try std.fmt.allocPrint(fba.allocator(), "Components - {s}0###Components", .{entity.GetName()});
        name[name.len - 1] = 0;
        _ = imgui.igBegin(name.ptr, null, 0);
    } else {
        _ = imgui.igBegin("Components - No Entity###Components", null, 0);
    }
    defer imgui.igEnd();

    if (self.mSelectedEntity) |entity| {
        //if (imgui.igButton("Add Component", .{ .x = 10, .y = 10 }) == true) {
        //    imgui.igOpenPopup_Str("AddComponent", imgui.ImGuiPopupFlags_None);
        //}
        //if (imgui.igBeginPopup("AddComponent", imgui.ImGuiWindowFlags_None) == true) {}
        try entity.EntityImguiRender();
    }
}

pub fn OnImguiEvent(self: *ComponentsPanel, event: *ImguiEvent) void {
    switch (event.*) {
        .ET_TogglePanelEvent => self.OnTogglePanelEvent(),
        else => @panic("Response to that event has not bee implemented yet in ComponentsPanel!\n"),
    }
}

pub fn OnTogglePanelEvent(self: *ComponentsPanel) void {
    self._P_Open = !self._P_Open;
}

pub fn OnSelectEntityEvent(self: *ComponentsPanel, new_selected_entity: ?Entity) void {
    self.mSelectedEntity = new_selected_entity;
}
