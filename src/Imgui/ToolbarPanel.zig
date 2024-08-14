const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const ToolbarPanel = @This();

_P_Open: bool = true,

pub fn Init(self: *ToolbarPanel) void {
    self._P_Open = true;
}

pub fn OnImguiRender(self: ToolbarPanel) void {
    if (self._P_Open == true) {
        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_WindowPadding, .{ .x = 0.0, .y = 2.0 });
        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_ItemInnerSpacing, .{ .x = 0.0, .y = 0.0 });
        imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 });
        const colors = imgui.igGetStyle().*.Colors;
        const buttonHovered = colors[imgui.ImGuiCol_ButtonHovered];
        const buttonActive = colors[imgui.ImGuiCol_ButtonActive];
        imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonHovered, .{ .x = buttonHovered.x, .y = buttonHovered.y, .z = buttonHovered.z, .w = 0.5 });
        imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonActive, .{ .x = buttonActive.x, .y = buttonActive.y, .z = buttonActive.z, .w = 0.5 });

        const config = imgui.ImGuiWindowFlags_NoDecoration | imgui.ImGuiWindowFlags_NoScrollbar | imgui.ImGuiWindowFlags_NoScrollWithMouse;
        _ = imgui.igBegin("##Toolbar", null, config);

        imgui.igPopStyleVar(2);
        imgui.igPopStyleColor(3);
        imgui.igEnd();
    }
}

pub fn OnImguiEvent(self: *ToolbarPanel, event: *ImguiEvent) void {
    switch (event.*) {
        .ET_TogglePanelEvent => {
            if (self._P_Open == true) {
                self._P_Open = false;
            } else {
                self._P_Open = true;
            }
        },
        .ET_NewProjectEvent => {
            std.debug.print("not impelmeneted yet :)", .{});
        },
    }
}
