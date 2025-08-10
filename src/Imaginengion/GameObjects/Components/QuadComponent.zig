const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const Vec4f32 = @import("../../Math/LinAlg.zig").Vec4f32;
const Vec2f32 = @import("../../Math/LinAlg.zig").Vec2f32;
const AssetM = @import("../../Assets/AssetManager.zig");
const Texture2D = @import("../../Assets/Assets/Texture2D.zig");
const AssetHandle = @import("../../Assets/AssetHandle.zig");
const AssetType = @import("../../Assets/AssetManager.zig").AssetType;
const QuadComponent = @This();

//IMGUI
const imgui = @import("../../Core/CImports.zig").imgui;
const EditorWindow = @import("../../Imgui/EditorWindow.zig");

mShouldRender: bool = true,
mColor: Vec4f32 = .{ 1.0, 1.0, 1.0, 1.0 },
mTexture: AssetHandle = .{ .mID = AssetHandle.NullHandle },
mTilingFactor: f32 = 1.0,
mTexCoords: [2]Vec2f32 = [2]Vec2f32{
    Vec2f32{ 0, 0 },
    Vec2f32{ 1, 1 },
},

pub fn Deinit(_: *QuadComponent) !void {}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == QuadComponent) {
            break :blk i;
        }
    }
};

pub fn GetEditorWindow(self: *QuadComponent) EditorWindow {
    return EditorWindow.Init(self);
}

pub fn GetName(self: QuadComponent) []const u8 {
    _ = self;
    return "QuadComponent";
}

pub fn GetInd(self: QuadComponent) u32 {
    _ = self;
    return @intCast(Ind);
}

pub fn EditorRender(self: *QuadComponent) !void {
    _ = imgui.igCheckbox("Should Render?", &self.mShouldRender);
    _ = imgui.igColorEdit4("Color", @ptrCast(&self.mColor), imgui.ImGuiColorEditFlags_None);
    _ = imgui.igDragFloat("TilingFactor", &self.mTilingFactor, 0.0, 0.0, 0.0, "%.2f", imgui.ImGuiSliderFlags_None);
    const texture_id = @as(*anyopaque, @ptrFromInt(@as(usize, (try self.mTexture.GetAsset(Texture2D)).GetID())));
    imgui.igImage(
        texture_id,
        .{ .x = 50.0, .y = 50.0 },
        .{ .x = 0.0, .y = 1.0 },
        .{ .x = 1.0, .y = 0.0 },
        .{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 },
        .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 },
    );
    if (imgui.igBeginDragDropTarget() == true) {
        if (imgui.igAcceptDragDropPayload("PNGLoad", imgui.ImGuiDragDropFlags_None)) |payload| {
            const path_len = payload.*.DataSize;
            const path = @as([*]const u8, @ptrCast(@alignCast(payload.*.Data)))[0..@intCast(path_len)];
            if (self.mTexture.mID != AssetHandle.NullHandle) {
                AssetM.ReleaseAssetHandleRef(&self.mTexture);
            }
            self.mTexture = try AssetM.GetAssetHandleRef(path, .Prj);
        }
    }
}
