const ComponentsList = @import("../Components.zig").ComponentsList;
const NameComponent = @This();

//IMGUI
const imgui = @import("../../Core/CImports.zig").imgui;
const EditorWindow = @import("../../Imgui/EditorWindow.zig");

Name: [24]u8,

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == NameComponent) {
            break :blk i;
        }
    }
};

pub fn GetEditorWindow(self: *NameComponent) EditorWindow {
    return EditorWindow.Init(self);
}

pub fn ImguiRender(self: *NameComponent) void {
    var buffer: [24]u8 = undefined;
    @memset(&buffer, 0);
    @memcpy(&buffer, &self.Name);

    if (imgui.igInputText("##Name", &buffer, buffer.len, imgui.ImGuiInputTextFlags_None, null, null) == true) {
        self.Name = buffer;
    }
}
