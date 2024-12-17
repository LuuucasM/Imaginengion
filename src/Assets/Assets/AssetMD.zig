const AssetType = @import("../Assets.zig").EAssets;

pub const AssetState = enum {
    Unloaded,
    Loading,
    Loaded,
    Evicted,
};

mMemoryLocation: *anyopaque, //for if its in cpu memory
mGPuLocation: u32, //for if its in gpu memory
mAssetState: AssetState,
mAssetType: AssetType,
mRef: u32,
