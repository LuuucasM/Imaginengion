const AssetsList = @import("../Assets.zig").AssetsList;
const IDComponent = @This();

ID: u128,

pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == IDComponent) {
            break :blk i;
        }
    }
};

//afaik this component doesnt need to be
//imgui rendered ever
