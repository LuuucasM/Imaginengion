const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const AssetMetaData = @This();
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;

mRefs: usize = 0,

pub fn Deinit(_: *AssetMetaData) !void {}

pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == AssetMetaData) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

pub const Category: ComponentCategory = .Unique;
