const AssetsList = @import("../Assets.zig").AssetsList;
const AssetMetaData = @This();

mRefs: u32,

pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == AssetMetaData) {
            break :blk i;
        }
    }
};
