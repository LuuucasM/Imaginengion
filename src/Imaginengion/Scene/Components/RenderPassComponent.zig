const std = @import("std");
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const RenderPassComponent = @This();

const AssetHandle = @import("../../Assets/AssetHandle.zig");
const SceneLayer = @import("../SceneLayer.zig");
const SceneType = @import("../SceneManager.zig").SceneType;

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == RenderPassComponent) {
            break :blk i;
        }
    }
};

mFirst: SceneType = SceneLayer.NullScene,
mPrev: SceneType = SceneLayer.NullScene,
mNext: SceneType = SceneLayer.NullScene,
mParent: SceneType = SceneLayer.NullScene,
mRenderPassAssetHandle: AssetHandle = .{ .mID = AssetHandle.NullHandle },

pub fn Deinit(_: *RenderPassComponent) !void {}

pub fn GetName(self: RenderPassComponent) []const u8 {
    _ = self;
    return "RenderPassComponent";
}

pub fn GetInd(self: RenderPassComponent) u32 {
    _ = self;
    return @intCast(Ind);
}
