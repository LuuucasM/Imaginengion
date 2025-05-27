const std = @import("std");
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const RenderFeatureComponent = @This();

const AssetHandle = @import("../../Assets/AssetHandle.zig");
const SceneLayer = @import("../SceneLayer.zig");
const SceneType = @import("../SceneManager.zig").SceneType;

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == RenderFeatureComponent) {
            break :blk i;
        }
    }
};

mFirst: SceneType = SceneLayer.NullScene,
mPrev: SceneType = SceneLayer.NullScene,
mNext: SceneType = SceneLayer.NullScene,
mParent: SceneType = SceneLayer.NullScene,
mRenderPassAssetHandle: AssetHandle = .{ .mID = AssetHandle.NullHandle },

pub fn Deinit(_: *RenderFeatureComponent) !void {}

pub fn GetName(self: RenderFeatureComponent) []const u8 {
    _ = self;
    return "RenderFeatureComponent";
}

pub fn GetInd(self: RenderFeatureComponent) u32 {
    _ = self;
    return @intCast(Ind);
}
