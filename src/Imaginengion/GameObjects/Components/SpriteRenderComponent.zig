const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const Vec4f32 = @import("../../Math/LinAlg.zig").Vec4f32;
const AssetM = @import("../../Assets/AssetManager.zig");
const Texture2D = @import("../../Assets/Assets/Texture2D.zig");
const AssetHandle = @import("../../Assets/AssetHandle.zig");
const SpriteRenderComponent = @This();

//IMGUI
const imgui = @import("../../Core/CImports.zig").imgui;
const EditorWindow = @import("../../Imgui/EditorWindow.zig");

mShouldRender: bool = true,
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
    _ = imgui.igCheckbox("Should Render?", &self.mShouldRender);
    _ = imgui.igColorEdit4("Color", @ptrCast(&self.mColor), imgui.ImGuiColorEditFlags_None);

    const texture_id = @as(*anyopaque, @ptrFromInt(@as(usize, (try self.mTexture.GetAsset(Texture2D)).GetID())));
    imgui.igImage(
        texture_id,
        .{ .x = 50.0, .y = 50.0 },
        .{ .x = 0.0, .y = 0.0 },
        .{ .x = 1.0, .y = 1.0 },
        .{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 },
        .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 },
    );
    if (imgui.igBeginDragDropTarget() == true) {
        if (imgui.igAcceptDragDropPayload("PNGLoad", imgui.ImGuiDragDropFlags_None)) |payload| {
            const path_len = payload.*.DataSize;
            const path = @as([*]const u8, @ptrCast(@alignCast(payload.*.Data)))[0..@intCast(path_len)];
            if (self.mTexture.mID != std.math.maxInt(u32)) {
                AssetM.ReleaseAssetHandleRef(self.mTexture.mID);
            }
            self.mTexture = try AssetM.GetAssetHandleRef(path, .Prj);
        }
    }
}
