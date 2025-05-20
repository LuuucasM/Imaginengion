const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const AssetMetaData = @This();

mRefs: usize = 0,

pub fn Deinit(_: *AssetMetaData) !void {}

pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == AssetMetaData) {
            break :blk i;
        }
    }
};
