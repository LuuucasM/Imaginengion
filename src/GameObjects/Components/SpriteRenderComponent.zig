const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const Vec4f32 = @import("../../Math/LinAlg.zig").Vec4f32;
const AssetM = @import("../../Assets/AssetManager.zig");
const AssetHandle = @import("../../Assets/AssetHandle.zig");
const SpriteRenderComponent = @This();

//IMGUI
const imgui = @import("../../Core/CImports.zig").imgui;
const EditorWindow = @import("../../Imgui/EditorWindow.zig");

mColor: Vec4f32 = .{ 1.0, 1.0, 1.0, 1.0 },
mTexture: AssetHandle = .{ .mID = std.math.maxInt(u32) },
mTilingFactor: f32 = 1.0,

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == SpriteRenderComponent) {
            break :blk i;
        }
    }
};

pub fn GetEditorWindow(self: *SpriteRenderComponent) EditorWindow {
    return EditorWindow.Init(self);
}

pub fn GetName(self: SpriteRenderComponent) []const u8 {
    _ = self;
    return "SpriteRenderComponent";
}

pub fn GetInd(self: SpriteRenderComponent) u32 {
    _ = self;
    return @intCast(Ind);
}

pub fn EditorRender(self: *SpriteRenderComponent) !void {
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
