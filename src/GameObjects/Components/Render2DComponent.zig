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

const Shape2D = enum {
    Rect,
    Sprite,
    Circle,
    Line,
};

mTexture: AssetHandle,
mColor: Vec4f32,
mTilingFactor: f32,
mShape2D: Shape2D,

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
