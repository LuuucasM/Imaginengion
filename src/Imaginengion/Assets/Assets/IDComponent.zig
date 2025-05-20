const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const IDComponent = @This();

ID: u128 = std.math.maxInt(u128),

pub fn Deinit(_: *IDComponent) !void {}

pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == IDComponent) {
            break :blk i;
        }
    }
};
