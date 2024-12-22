const std = @import("std");
const AssetManager = @import("AssetManager.zig");
const AssetHandle = @This();

mID: u32,

pub fn GetAsset(self: AssetHandle, comptime ComponentType: type) *ComponentType {
    comptime {
        const AssetMetaData = @import("./Assets/AssetMetaData.zig");
        const FileMetaData = @import("./Assets/FileMetaData.zig");
        if (ComponentType == AssetMetaData or ComponentType == FileMetaData) {
            @compileError("Cannot call AssetHandle.GetAsset with AssetMetaData or FileMetaData");
        }
    }
    return AssetManager.GetComponent(ComponentType, self.mID);
}
