const ComponentsList = @import("../Components.zig").ComponentsList;
const TransformComponent = @This();
const LinAlg = @import("../../Math/LinAlg.zig");

//imgui stuff
const imgui = @import("../../Core/CImports.zig").imgui;
const EditorWindow = @import("../../Imgui/EditorWindow.zig");

const Vec3f32 = LinAlg.Vec3f32;
const Quatf32 = LinAlg.Quatf32;
const Mat4f32 = LinAlg.Mat4f32;

Translation: Vec3f32,
Rotation: Quatf32,
Scale: Vec3f32,

Transform: Mat4f32,
Dirty: bool,

pub fn GetTransformMatrix(self: *TransformComponent) Mat4f32 {
    if (self.Dirty == true) {
        defer self.Dirty = false;

        self.Transform = LinAlg.Translate(self.Translation) * LinAlg.QuatToMat4(self.Rotation) * LinAlg.Scale(self.Scale);
    }
    return self.Transform;
}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == TransformComponent) {
            break :blk i;
        }
    }
};

pub fn GetEditorWindow(self: *TransformComponent) EditorWindow {
    return EditorWindow.Init(self);
}

pub fn ImguiRender(self: *TransformComponent) void {
    const tree_node_flags: u32 = imgui.ImGuiTreeNodeFlags_DefaultOpen | imgui.ImGuiTreeNodeFlags_AllowOverlap | imgui.ImGuiTreeNodeFlags_Framed |
        imgui.ImGuiTreeNodeFlags_SpanAvailWidth | imgui.ImGuiTreeNodeFlags_FramePadding;
    const is_tree_open = imgui.igTreeNodeEx_Str(@typeName(TransformComponent), tree_node_flags);

    if (is_tree_open) {
        defer imgui.igTreePop();
        _ = DrawVec3Control("Translation", &self.Translation, 0.0, 0.075, 100.0);
        var rotation = LinAlg.QuatToDegrees(self.Rotation); //TODO: IMPLEMENT LIN ALG FUNCTION
        if (DrawVec3Control("Rotation", &rotation, 0.0, 0.25, 100.0) == true) {
            self.Rotation = LinAlg.DegreesToQuat(rotation); //TODO: IMPLEMENT LIN ALG FUNCTION
        }
        _ = DrawVec3Control("Scale", &self.Scale, 1.0, 0.075, 100.0);
    }
}

fn DrawVec3Control(label: []const u8, values: *LinAlg.Vec3f32, reset_value: f32, speed: f32, column_width: f32) bool {
    const io = imgui.igGetIO();
    const bold_font = io.*.Fonts.*.Fonts.Data[0];
    var changed: bool = false;

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
    const line_height = imgui.igGetIO().*.FontDefault.*.FontSize + imgui.igGetStyle().*.FramePadding.y * 2.0;
    const button_size = imgui.ImVec2{ .x = line_height, .y = line_height };

    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, imgui.ImVec4{ .x = 0.478, .y = 0.156, .z = 0.156, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonHovered, imgui.ImVec4{ .x = 0.717, .y = 0.234, .z = 0.234, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonActive, imgui.ImVec4{ .x = 0.597, .y = 0.195, .z = 0.195, .w = 1.0 });

    imgui.igPushFont(bold_font);
    if (imgui.igButton("X", button_size)) {
        values.* = @as(Vec3f32, @splat(reset_value));
        changed = true;
    }
    imgui.igPopFont();

    imgui.igPopStyleColor(3);

    imgui.igSameLine(0.0, 0.0);
    if (imgui.igDragFloat("##X", &values[0], speed, 0.0, 0.0, "%.2f", imgui.ImGuiSliderFlags_None)) {
        changed = true;
    }
    imgui.igPopItemWidth();
    imgui.igSameLine(0.0, 0.0);

    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, imgui.ImVec4{ .x = 0.156, .y = 0.478, .z = 0.156, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonHovered, imgui.ImVec4{ .x = 0.234, .y = 0.717, .z = 0.234, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonActive, imgui.ImVec4{ .x = 0.195, .y = 0.597, .z = 0.195, .w = 1.0 });

    imgui.igPushFont(bold_font);
    if (imgui.igButton("Y", button_size)) {
        values.* = @as(Vec3f32, @splat(reset_value));
        changed = true;
    }
    imgui.igPopFont();

    imgui.igPopStyleColor(3);

    imgui.igSameLine(0.0, 0.0);
    if (imgui.igDragFloat("##Y", &values[1], speed, 0.0, 0.0, "%.2f", imgui.ImGuiSliderFlags_None)) {
        changed = true;
    }
    imgui.igPopItemWidth();
    imgui.igSameLine(0.0, 0.0);

    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, imgui.ImVec4{ .x = 0.156, .y = 0.306, .z = 0.478, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonHovered, imgui.ImVec4{ .x = 0.234, .y = 0.459, .z = 0.717, .w = 1.0 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonActive, imgui.ImVec4{ .x = 0.195, .y = 0.328, .z = 0.597, .w = 1.0 });

    imgui.igPushFont(bold_font);
    if (imgui.igButton("Z", button_size)) {
        values.* = @as(Vec3f32, @splat(reset_value));
        changed = true;
    }
    imgui.igPopFont();

    imgui.igPopStyleColor(3);

    imgui.igSameLine(0.0, 0.0);
    if (imgui.igDragFloat("##Z", &values[2], speed, 0.0, 0.0, "%.2f", imgui.ImGuiSliderFlags_None)) {
        changed = true;
    }
    imgui.igPopItemWidth();

    return changed;
}
