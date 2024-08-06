const imgui = @import("../Core/CImports.zig").imgui;
const ComponentsPanel = @This();
pub fn OnImguiRender(self: ComponentsPanel) void {
    _ = self;
    _ = imgui.igBegin("Components", null, 0);
    imgui.igEnd();
}
