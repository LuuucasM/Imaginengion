const std = @import("std");
const AssetManager = @import("AssetManager.zig");
const AssetHandle = @This();
pub const EmptyHandle = std.math.maxInt(AssetManager.AssetType);

mID: AssetManager.AssetType,

pub fn GetAsset(self: *AssetHandle, comptime component_type: type) !*component_type {
    comptime {
        const Assets = @import("Assets.zig");
        const AssetMetaData = Assets.AssetMetaData;
        const FileMetaData = Assets.FileMetaData;
        const IDComponent = Assets.IDComponent;
        const Texture2D = Assets.Texture2D;
        const ScriptAsset = Assets.ScriptAsset;

        if (component_type == AssetMetaData) {
            @compileError("Cannot call AssetHandle.GetAsset with AssetMetaData\n");
        }
        if (component_type != Texture2D and component_type != IDComponent and component_type != FileMetaData and component_type != ScriptAsset) {
            @compileError("Cannot call AssetHandle.GetAsset with a non-asset type!\n");
        }
    }
    return try AssetManager.GetAsset(component_type, self.mID);
}
