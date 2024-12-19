const AssetsList = @import("../Assets.zig").AssetsList;
const FileMetaData = @This();

mAbsPath: []const u8,
mLastModified: i128,
mSize: u64,
mHash: u64,

pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == FileMetaData) {
            break :blk i;
        }
    }
};
