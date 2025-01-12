const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const Vec4f32 = @import("../../Math/LinAlg.zig").Vec4f32;
const CircleRenderComponent = @This();

//IMGUI
const imgui = @import("../../Core/CImports.zig").imgui;
const EditorWindow = @import("../../Imgui/EditorWindow.zig");

mColor: Vec4f32,
mThickness: f32,
mFade: f32,

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == CircleRenderComponent) {
            break :blk i;
        }
    }
};

pub fn GetEditorWindow(self: *CircleRenderComponent) EditorWindow {
    return EditorWindow.Init(self);
}

pub fn GetName(self: CircleRenderComponent) []const u8 {
    _ = self;
    return "CircleRenderComponent";
}

pub fn GetInd(self: CircleRenderComponent) u32 {
    _ = self;
    return @intCast(Ind);
}

pub fn EditorRender(self: *CircleRenderComponent) !void {
    _ = imgui.igColorEdit4("Color", @ptrCast(&self.Color), imgui.ImGuiColorEditFlags_None);
}
