const imgui = @import("../Core/CImports.zig").imgui;
const ContentBrowserPanel = @This();
pub fn OnImguiRender(self: ContentBrowserPanel) void {
    _ = self;
    _ = imgui.igBegin("ContentBrowser", null, 0);
    imgui.igEnd();
}
