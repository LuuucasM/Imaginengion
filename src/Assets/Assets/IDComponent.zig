const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const GenUUID = @import("../../Core/UUID.zig").GenUUID;
const IDComponent = @This();

ID: u128,

pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == IDComponent) {
            break :blk i;
        }
    }
};
