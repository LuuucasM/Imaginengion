const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const RenderStats = @import("../Renderer/Renderer.zig").RenderStats;
const PlayPanel = @This();

pub fn Init() PlayPanel {
    return PlayPanel{};
}

pub fn OnImguiRender(self: PlayPanel) !void {
    if (self._P_Open == false) return;
    _ = imgui.igBegin("Stats", null, 0);
    defer imgui.igEnd();
}
