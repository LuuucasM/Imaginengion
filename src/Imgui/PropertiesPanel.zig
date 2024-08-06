const imgui = @import("../Core/CImports.zig").imgui;
const PropertiesPanel = @This();
pub fn OnImguiRender(self: PropertiesPanel) void {
    _ = self;
    _ = imgui.igBegin("Properties", null, 0);
    imgui.igEnd();
}
