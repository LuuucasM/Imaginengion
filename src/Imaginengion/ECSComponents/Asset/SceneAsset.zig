const std = @import("std");
const ComponentsList = @import("../AComponents.zig").ComponentsList;
const SceneAsset = @This();
const EngineContext = @import("../../Core/EngineContext.zig");
const Scene = @import("../../ECSObjects/Scene.zig");

pub const empty: SceneAsset = .{
    .mScene = .empty,
};

mScene: Scene,

pub fn Deinit(_: *SceneAsset, _: *EngineContext) !void {}

pub const Name: []const u8 = "SceneAsset";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |asset_type, i| {
        if (asset_type == SceneAsset) {
            break :blk i + 5;
        }
    }
};
