const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const FileMetaData = @This();

mAbsPath: []const u8 = undefined,
mLastModified: i128 = 0,
mSize: u64 = 0,
mHash: u64 = 0,

pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == FileMetaData) {
            break :blk i;
        }
    }
};
