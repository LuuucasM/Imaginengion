const ComponentsList = @import("../Components.zig").ComponentsList;
const Render2DComponent = @This();
const Vec4f32 = @import("../../Math/LinAlg.zig").Vec4f32;

//IMGUI
const imgui = @import("../../Core/CImports.zig").imgui;
const EditorWindow = @import("../../Imgui/EditorWindow.zig");

Texture: u64 = 0,
Color: Vec4f32 = .{ 1.0, 1.0, 1.0, 1.0 },
TilingFactor: f32 = 1.0,

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == Render2DComponent) {
            break :blk i;
        }
    }
};

pub fn GetEditorWindow(self: *Render2DComponent) EditorWindow {
    return EditorWindow.Init(self);
}

pub fn ImguiRender(self: *Render2DComponent) void {
    const padding: f32 = 16.0;
    const thumbnail_size: f32 = 70.0;
    _ = padding;
    _ = thumbnail_size;
    imgui.igColorEdit4("Color", &self.Color, imgui.ImGuiColorEditFlags_None);
    imgui.igText("TEMPORARY TEXTURE TARGET");
}
