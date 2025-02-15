const std = @import("std");
const AssetManager = @import("AssetManager.zig");
const AssetHandle = @This();
pub const EmptyHandle = std.math.maxInt(u32);
mID: u32,

pub fn GetAsset(self: *AssetHandle, comptime component_type: type) !*component_type {
    comptime {
        const Assets = @import("Assets.zig");
        const AssetMetaData = Assets.AssetMetaData;
        const FileMetaData = Assets.FileMetaData;
        const IDComponent = Assets.IDComponent;
        const Texture2D = Assets.Texture2D;

        if (component_type == AssetMetaData or component_type == FileMetaData) {
            @compileError("Cannot call AssetHandle.GetAsset with AssetMetaData or FileMetaData");
        }
        if (component_type != Texture2D and component_type != IDComponent) {
            @compileError("Cannot call AssetHandle.GetAsset with a non-asset type!");
        }
    }
    return try AssetManager.GetAsset(component_type, self.mID);
}
