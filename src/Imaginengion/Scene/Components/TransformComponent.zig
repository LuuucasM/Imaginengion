const std = @import("std");
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const LinAlg = @import("../../Math/LinAlg.zig");
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;
const EngineContext = @import("../../Core/EngineContext.zig");

//imgui stuff
const imgui = @import("../../Core/CImports.zig").imgui;

const Vec3f32 = LinAlg.Vec3f32;
const Quatf32 = LinAlg.Quatf32;
const Mat4f32 = LinAlg.Mat4f32;

const TransformComponent = @This();

Translation: Vec3f32 = .{ 0.0, 0.0, 0.0 },
Rotation: Quatf32 = .{ 1.0, 0.0, 0.0, 0.0 },
Scale: Vec3f32 = .{ 1.0, 1.0, 1.0 },

pub fn Deinit(_: *TransformComponent, _: *EngineContext) !void {}

pub fn SetTranslation(self: *TransformComponent, new_pos: Vec3f32) void {
    self.Translation = new_pos;
}
pub fn SetRotation(self: *TransformComponent, new_rot: Quatf32) void {
    self.Rotation = new_rot;
}
pub fn SetScale(self: *TransformComponent, new_scale: Vec3f32) void {
    self.Scale = new_scale;
}
pub fn GetLocalTransform(self: *TransformComponent) Mat4f32 {
    return LinAlg.Mat4MulMat4(LinAlg.Translate(self.Translation), LinAlg.Mat4MulMat4(LinAlg.QuatToMat4(self.Rotation), LinAlg.Scale(self.Scale)));
}

pub fn GetName(self: TransformComponent) []const u8 {
    _ = self;
    return "TransformComponent";
}

pub fn GetInd(self: TransformComponent) u32 {
    _ = self;
    return @intCast(Ind);
}

pub const Category: ComponentCategory = .Unique;

pub fn EditorRender(self: *TransformComponent) !void {
    DrawVec3Control("Translation", &self.Translation, 0.0, 0.075, 100.0);
    DrawVec3ControlRot("Rotation", &self.Rotation, Quatf32{ 1.0, 0.0, 0.0, 0.0 }, 0.25, 100.0);
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
    _ = imgui.igDragFloat("##X", &values[0], speed, 0.0, 0.0, "%.2f", imgui.ImGuiSliderFlags_None);
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
    _ = imgui.igDragFloat("##Y", &values[1], speed, 0.0, 0.0, "%.2f", imgui.ImGuiSliderFlags_None);
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
    _ = imgui.igDragFloat("##Z", &values[2], speed, 0.0, 0.0, "%.2f", imgui.ImGuiSliderFlags_None);
    imgui.igPopItemWidth();
}

fn DrawVec3ControlRot(label: []const u8, rotation: *Quatf32, reset_value: Quatf32, speed: f32, column_width: f32) void {
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
        rotation.* = reset_value;
    }
    imgui.igPopFont();

    imgui.igPopStyleColor(3);

    imgui.igSameLine(0.0, 0.0);
    const x_ang_saved = LinAlg.RadiansToDegrees(LinAlg.QuatToPitch(rotation.*));
    var x_ang = x_ang_saved;
    if (imgui.igDragFloat("##X", &x_ang, speed, 0.0, 0.0, "%.2f", imgui.ImGuiSliderFlags_None)) {
        const delta_theta = x_ang_saved - x_ang;
        const new_quat = LinAlg.QuatAngleAxis(delta_theta, Vec3f32{ 1.0, 0.0, 0.0 });
        rotation.* = LinAlg.QuatMulQuat(rotation.*, new_quat);
    }
    imgui.igPopItemWidth();
    imgui.igSameLine(0.0, 0.0);

    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, imgui.ImVec4{ .x = 0.156, .y = 0.478, .z = 0.156, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonHovered, imgui.ImVec4{ .x = 0.234, .y = 0.717, .z = 0.234, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonActive, imgui.ImVec4{ .x = 0.195, .y = 0.597, .z = 0.195, .w = 1.0 });

    imgui.igPushFont(bold_font);
    if (imgui.igButton("Y", button_size)) {
        rotation.* = reset_value;
    }
    imgui.igPopFont();

    imgui.igPopStyleColor(3);

    imgui.igSameLine(0.0, 0.0);

    const y_ang_saved = LinAlg.RadiansToDegrees(LinAlg.QuatToYaw(rotation.*));
    var y_ang = y_ang_saved;
    if (imgui.igDragFloat("##Y", &y_ang, speed, 0.0, 0.0, "%.2f", imgui.ImGuiSliderFlags_None)) {
        const delta_theta = y_ang_saved - y_ang;
        const new_quat = LinAlg.QuatAngleAxis(delta_theta, Vec3f32{ 0.0, 1.0, 0.0 });
        rotation.* = LinAlg.QuatMulQuat(rotation.*, new_quat);
    }
    imgui.igPopItemWidth();
    imgui.igSameLine(0.0, 0.0);

    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, imgui.ImVec4{ .x = 0.156, .y = 0.306, .z = 0.478, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonHovered, imgui.ImVec4{ .x = 0.234, .y = 0.459, .z = 0.717, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonActive, imgui.ImVec4{ .x = 0.195, .y = 0.328, .z = 0.597, .w = 1.0 });

    imgui.igPushFont(bold_font);
    if (imgui.igButton("Z", button_size)) {
        rotation.* = reset_value;
    }
    imgui.igPopFont();

    imgui.igPopStyleColor(3);

    imgui.igSameLine(0.0, 0.0);
    const z_ang_saved = LinAlg.RadiansToDegrees(LinAlg.QuatToRoll(rotation.*));
    var z_ang = z_ang_saved;
    if (imgui.igDragFloat("##Z", &z_ang, speed, 0.0, 0.0, "%.2f", imgui.ImGuiSliderFlags_None)) {
        const delta_theta = z_ang_saved - z_ang;
        const new_quat = LinAlg.QuatAngleAxis(delta_theta, Vec3f32{ 0.0, 0.0, 1.0 });
        rotation.* = LinAlg.QuatMulQuat(rotation.*, new_quat);
    }
    imgui.igPopItemWidth();
}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == TransformComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};
