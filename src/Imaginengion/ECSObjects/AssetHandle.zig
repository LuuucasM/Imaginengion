const std = @import("std");
const AssetManager = @import("../ECSManagers/AManager.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Components = @import("../ECSComponents/AComponents.zig");
const FileMetaData = Components.FileMetaData;
const ECSCore = @import("ECSObject.zig").Core;

const AssetHandle = @This();
pub const Type = u32;
pub const NullObject: Type = std.math.maxInt(Type);

const Core = ECSCore(AssetHandle);

pub const uninit: AssetHandle = .{
    .mID = NullObject,
    .mManager = undefined,
};

mID: AssetManager.AssetType,
mManager: *AssetManager,

pub fn GetAsset(self: AssetHandle, engine_context: *EngineContext, comptime component_type: type) !*component_type {
    return try self.mAssetManager.GetAsset(engine_context, component_type, self.mID);
}

pub fn GetFileMetaData(self: AssetHandle) *FileMetaData {
    return self.mAssetManager.GetFileMetaData(self.mID);
}

pub fn ReleaseAsset(self: *AssetHandle) void {
    if (self.mID != NullObject) {
        self.mAssetManager.ReleaseAssetHandleRef(self);
    }
}

pub const GetName = Core.GetName;
pub const IsActive = Core.IsActive;
pub const Invalidate = Core.Invalidate;
pub const IsIDValid = Core.IsIDValid;

pub fn jsonStringify(self: *const AssetHandle, jw: anytype) !void {
    const fmd = self.GetFileMetaData();
    try jw.objectField("AssetPath");
    try jw.write(fmd.mRelPath.items);
    try jw.objectField("PathType");
    try jw.write(fmd.mPathType);
}
