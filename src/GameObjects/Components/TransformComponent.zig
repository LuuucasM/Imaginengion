const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const LinAlg = @import("../../Math/LinAlg.zig");
const Entity = @import("../Entity.zig");
const TransformComponent = @This();

//imgui stuff
const imgui = @import("../../Core/CImports.zig").imgui;
const ImguiManager = @import("../../Imgui/Imgui.zig");
const ImguiEvent = @import("../../Imgui/ImguiEvent.zig").ImguiEvent;
const EditorWindow = @import("../../Imgui/EditorWindow.zig");

const Vec3f32 = LinAlg.Vec3f32;
const Quatf32 = LinAlg.Quatf32;
const Mat4f32 = LinAlg.Mat4f32;

Translation: Vec3f32,
Rotation: Quatf32,
Scale: Vec3f32,

Transform: Mat4f32,
Dirty: bool,

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == TransformComponent) {
            break :blk i;
        }
    }
};

pub fn GetTransformMatrix(self: *TransformComponent) Mat4f32 {
    if (self.Dirty == true) {
        defer self.Dirty = false;

        self.Transform = LinAlg.Translate(self.Translation) * LinAlg.QuatToMat4(self.Rotation) * LinAlg.Scale(self.Scale);
    }
    return self.Transform;
}

pub fn GetEditorWindow(self: *TransformComponent) EditorWindow {
    return EditorWindow.Init(self);
}

pub fn GetName(self: TransformComponent) []const u8 {
    _ = self;
    return "TransformComponent";
}

pub fn GetInd(self: TransformComponent) u32 {
    _ = self;
    return @intCast(Ind);
}

pub fn EditorRender(self: *TransformComponent) !void {
    DrawVec3Control("Translation", &self.Translation, 0.0, 0.075, 100.0);

    var rotation = LinAlg.QuatToDegrees(self.Rotation);
    DrawVec3Control("Rotation", &rotation, 0.0, 0.25, 100.0);
    self.Rotation = LinAlg.DegreesToQuat(rotation);

    DrawVec3Control("Scale", &self.Scale, 1.0, 0.075, 100.0);
}

fn DrawVec3Control(label: []const u8, values: *LinAlg.Vec3f32, reset_value: f32, speed: f32, column_width: f32) void {
    const io = imgui.igGetIO();
    const bold_font = io.*.Fonts.*.Fonts.Data[0];
    imgui.igPushID_Str(label.ptr);
    defer imgui.igPopID();

    imgui.igColumns(2, 0, false);
    defer imgui.igColumns(1, 0, false);
    imgui.igSetColumnWidth(0, column_width);
    imgui.igText(label.ptr);
    imgui.igNextColumn();

    imgui.igPushMultiItemsWidths(3, imgui.igCalcItemWidth());
    imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_ItemSpacing, .{ .x = 0.0, .y = 0.0 });
    defer imgui.igPopStyleVar(1);

    const line_height = bold_font.*.FontSize + imgui.igGetStyle().*.FramePadding.y * 2.0;
    const button_size = imgui.ImVec2{ .x = line_height, .y = line_height };

    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, imgui.ImVec4{ .x = 0.478, .y = 0.156, .z = 0.156, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonHovered, imgui.ImVec4{ .x = 0.717, .y = 0.234, .z = 0.234, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonActive, imgui.ImVec4{ .x = 0.597, .y = 0.195, .z = 0.195, .w = 1.0 });

    imgui.igPushFont(bold_font);
    if (imgui.igButton("X", button_size)) {
        values.*[0] = reset_value;
    }
    imgui.igPopFont();

    imgui.igPopStyleColor(3);

    imgui.igSameLine(0.0, 0.0);
    if (imgui.igDragFloat("##X", &values[0], speed, 0.0, 0.0, "%.2f", imgui.ImGuiSliderFlags_None)) {}
    imgui.igPopItemWidth();
    imgui.igSameLine(0.0, 0.0);

    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, imgui.ImVec4{ .x = 0.156, .y = 0.478, .z = 0.156, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonHovered, imgui.ImVec4{ .x = 0.234, .y = 0.717, .z = 0.234, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonActive, imgui.ImVec4{ .x = 0.195, .y = 0.597, .z = 0.195, .w = 1.0 });

    imgui.igPushFont(bold_font);
    if (imgui.igButton("Y", button_size)) {
        values.*[1] = reset_value;
    }
    imgui.igPopFont();

    imgui.igPopStyleColor(3);

    imgui.igSameLine(0.0, 0.0);
    if (imgui.igDragFloat("##Y", &values[1], speed, 0.0, 0.0, "%.2f", imgui.ImGuiSliderFlags_None)) {}
    imgui.igPopItemWidth();
    imgui.igSameLine(0.0, 0.0);

    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, imgui.ImVec4{ .x = 0.156, .y = 0.306, .z = 0.478, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonHovered, imgui.ImVec4{ .x = 0.234, .y = 0.459, .z = 0.717, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonActive, imgui.ImVec4{ .x = 0.195, .y = 0.328, .z = 0.597, .w = 1.0 });

    imgui.igPushFont(bold_font);
    if (imgui.igButton("Z", button_size)) {
        values.*[2] = reset_value;
    }
    imgui.igPopFont();

    imgui.igPopStyleColor(3);

    imgui.igSameLine(0.0, 0.0);
    if (imgui.igDragFloat("##Z", &values[2], speed, 0.0, 0.0, "%.2f", imgui.ImGuiSliderFlags_None)) {}
    imgui.igPopItemWidth();
}
