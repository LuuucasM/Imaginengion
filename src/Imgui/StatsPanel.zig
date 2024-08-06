const imgui = @import("../Core/CImports.zig").imgui;
const StatsPanel = @This();
pub fn OnImguiRender(self: StatsPanel) void {
    _ = self;
    _ = imgui.igBegin("Stats", null, 0);
    imgui.igEnd();
}
