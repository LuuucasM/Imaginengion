const ECSManager = @import("../ECS/ECSManager.zig");
const AssetHandle = @This();

mID: u32,
mECS: *ECSManager,
