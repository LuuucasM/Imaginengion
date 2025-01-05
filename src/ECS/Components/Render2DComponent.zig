const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const Vec4f32 = @import("../../Math/LinAlg.zig").Vec4f32;
const AssetM = @import("../../Assets/AssetManager.zig");
const AssetHandle = @import("../../Assets/AssetHandle.zig");
const Entity = @import("../Entity.zig");
const Render2DComponent = @This();

//IMGUI
const imgui = @import("../../Core/CImports.zig").imgui;
const EditorWindow = @import("../../Imgui/EditorWindow.zig");
const ImguiManager = @import("../../Imgui/Imgui.zig");
const ImguiEvent = @import("../../Imgui/ImguiEvent.zig").ImguiEvent;

Texture: AssetHandle,
Color: Vec4f32,
TilingFactor: f32,

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

pub fn ImguiRender(self: *Render2DComponent, entity: Entity) !void {
    if (imgui.igSelectable_Bool(@typeName(Render2DComponent), false, imgui.ImGuiSelectableFlags_None, .{ .x = 0, .y = 0 }) == true) {
        const new_event = ImguiEvent{
            .ET_SelectComponentEvent = .{
                .mEditorWindow = EditorWindow.Init(self, entity),
            },
        };
        try ImguiManager.InsertEvent(new_event);
    }
}

pub fn NotComponentRender() bool {
    if (imgui.igMenuItem_Bool("Render2DComponent", "", false, true) == true) {
        imgui.igCloseCurrentPopup();
        return true;
    }
    return false;
}

pub fn GetName(self: Render2DComponent) []const u8 {
    _ = self;
    return "Render2DComponent";
}

pub fn GetInd(self: Render2DComponent) u32 {
    _ = self;
    return @intCast(Ind);
}

pub fn EditorRender(self: *Render2DComponent) !void {
    const padding: f32 = 16.0;
    const thumbnail_size: f32 = 70.0;
    _ = padding;
    _ = thumbnail_size;
    _ = imgui.igColorEdit4("Color", @ptrCast(&self.Color), imgui.ImGuiColorEditFlags_None);
    imgui.igText("TEMPORARY TEXTURE TARGET");
    if (imgui.igBeginDragDropTarget() == true) {
        if (imgui.igAcceptDragDropPayload("PNGLoad", imgui.ImGuiDragDropFlags_None)) |payload| {
            const path_len = payload.*.DataSize;
            const path = @as([*]const u8, @ptrCast(@alignCast(payload.*.Data)))[0..@intCast(path_len)];
            self.Texture = try AssetM.GetAssetHandleRef(path);
        }
    }
}
