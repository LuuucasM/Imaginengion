const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const AssetMetaData = @This();
const EngineContext = @import("../../Core/EngineContext.zig");

mRefs: usize = 0,

pub fn Deinit(_: *AssetMetaData, _: *EngineContext) !void {}

pub const Name: []const u8 = "AssetMetaData";
pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == AssetMetaData) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};
