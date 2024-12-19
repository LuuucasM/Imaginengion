const ECSManager = @import("../ECS/ECSManager.zig");
const AssetMetaData = @import("./Assets/AssetMetaData.zig");
const AssetState = AssetMetaData.AssetState;
const AssetHandle = @This();

mID: u32,
mECSRef: *ECSManager,

pub fn EnsureLoaded(self: AssetHandle) AssetState {
    _ = self;
    //put something here
}
