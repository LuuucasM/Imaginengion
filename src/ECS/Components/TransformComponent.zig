const imgui = @import("../../Core/CImports.zig").imgui;
const ComponentsList = @import("../Components.zig").ComponentsList;
const TransformComponent = @This();
const LinAlg = @import("../../Math/LinAlg.zig");

Translation: LinAlg.Vec3f32,
Rotation: LinAlg.Quatf32,
Scale: LinAlg.Vec3f32,

TransformMatrix: LinAlg.Mat4f32,
Dirty: bool,

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == TransformComponent) {
            break :blk i;
        }
    }
};

pub fn ImguiRender(self: *TransformComponent) void {
    const is_tree_open = imgui.igTreeNodeEx_Str(@typeName(TransformComponent), tree_node_flags);

    if (is_tree_open) {
        defer imgui.igTreePop();
        _ = DrawVec3Control("Translation", &self.Translation, 0.0, 0.075, 100.0);
        const rotation = LinAlg.QuatToDegrees(self.Rotation); //TODO: IMPLEMENT LIN ALG FUNCTION
        if (DrawVec3Control("Rotation", &rotation, 0.0, 0.25, 100.0) == true){
            self.Rotation = LinAlg.DegreesToQuat(rotation); //TODO: IMPLEMENT LIN ALG FUNCTION
        }
        _ = DrawVec3Control("Scale", &self.Scale, 1.0, 0.075, 100.0);
    }
}

fn DrawVec3Control(label: []const u8, values: *LinAlg.Vec3f32, reset_value: f32, speed: f32, column_width: f32) bool{
    const io = imgui.igGetIO();
    const bold_font = io.Fonts.Font[0];

    var changed: bool = false;

    imgui.igPushID_Str(label.ptr);
    defer imgui.igPopID();

    imgui.igColumns(2);
    defer imgui.igColumns(1);
    imgui.igSetColumnWidth(0, column_width);
    imgui.igText(label.ptr);
    imgui.igNextColumn();

    imgui.igPushMultiItemsWidths(3, imgui.igCalcItemWidth());
    imgui.igPushStyleVar(ImGuiStyleVar_ItemSpacing, .{.x = 0.0, .y = 0.0});

    const line_height = imgui.GImGui.Fonts.FontSize + imgui.GImGui.Style.FramePadding.y * 2.0;
    const button_size = imgui.ImVec2{.x = line_height, .y = line_height};


}