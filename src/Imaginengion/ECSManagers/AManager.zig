const std = @import("std");

const ResolveReq = @import("../Serializer/Serializer.zig").ResolveReq;

const ECSManager = @import("../ECS/ECSManager.zig").ECSManager;

const Asset = @import("../ECSObjects/Asset.zig");
const AssetComponents = @import("../ECSComponents/AComponents.zig");
const AssetComponentsList = AssetComponents.ComponentsList;

pub const ECSManagerA = ECSManager(Asset.Type, &AssetComponentsList);

pub const PathType = enum {
    Eng,
    Prj,
    Gen,
};

mECSManagerGO: ECSManagerA = .empty,

mUUIDToWorldID: std.AutoHashMapUnmanaged(u64, usize) = .empty,
mResolveUUIDList: std.ArrayList(ResolveReq) = .empty,
