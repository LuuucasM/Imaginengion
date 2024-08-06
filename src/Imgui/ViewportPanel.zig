const imgui = @import("../Core/CImports.zig").imgui;
const ViewportPanel = @This();
pub fn OnImguiRender(self: ViewportPanel) void {
    _ = self;
    _ = imgui.igBegin("Viewport", null, 0);
    imgui.igEnd();
}
