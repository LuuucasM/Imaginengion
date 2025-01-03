const std = @import("std");
const AssetManager = @import("AssetManager.zig");
const AssetHandle = @This();
pub const EmptyHandle = std.math.maxInt(u32);
mID: u32,

pub fn GetAsset(self: *AssetHandle, comptime ComponentType: type) !*ComponentType {
    comptime {
        const AssetMetaData = @import("./Assets/AssetMetaData.zig");
        const FileMetaData = @import("./Assets/FileMetaData.zig");
        if (ComponentType == AssetMetaData or ComponentType == FileMetaData) {
            @compileError("Cannot call AssetHandle.GetAsset with AssetMetaData or FileMetaData");
        }
    }
    return try AssetManager.GetAsset(ComponentType, self.mID);
}
