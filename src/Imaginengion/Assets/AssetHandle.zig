const std = @import("std");
const AssetManager = @import("AssetManager.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const FileMetaData = @import("Assets/FileMetaData.zig");

const AssetHandle = @This();
pub const NullHandle = std.math.maxInt(AssetManager.AssetType);

pub const empty: AssetHandle = .{
    .mID = NullHandle,
    .mAssetManager = undefined,
};

mID: AssetManager.AssetType = NullHandle,
mAssetManager: *AssetManager = undefined,

pub fn GetAsset(self: AssetHandle, engine_context: *EngineContext, comptime component_type: type) !*component_type {
    return try self.mAssetManager.GetAsset(engine_context, component_type, self.mID);
}

pub fn GetFileMetaData(self: AssetHandle) *FileMetaData {
    return self.mAssetManager.GetFileMetaData(self.mID);
}

pub fn ReleaseAsset(self: *AssetHandle) void {
    if (self.mID != NullHandle) {
        self.mAssetManager.ReleaseAssetHandleRef(self);
    }
}

pub fn jsonStringify(self: *const AssetHandle, jw: anytype) !void {
    const fmd = self.GetFileMetaData();
    try jw.objectField("Texture");
    try jw.write(fmd.mRelPath.items);
    try jw.objectField("PathType");
    try jw.write(fmd.mPathType);
}
