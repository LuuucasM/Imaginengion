const imgui = @import("../Core/CImports.zig").imgui;
const ScenePanel = @This();
pub fn OnImguiRender(self: ScenePanel) void {
    _ = self;
    _ = imgui.igBegin("Scene", null, 0);
    imgui.igEnd();
}
