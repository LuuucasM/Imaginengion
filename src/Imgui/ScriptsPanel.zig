const imgui = @import("../Core/CImports.zig").imgui;
const ScriptsPanel = @This();
pub fn OnImguiRender(self: ScriptsPanel) void {
    _ = self;
    _ = imgui.igBegin("Scripts", null, 0);
    imgui.igEnd();
}
