const std = @import("std");
const AssetManager = @import("AssetManager.zig");
const EngineContext = @import("../Core/EngineContext.zig");

const AssetHandle = @This();
pub const NullHandle = std.math.maxInt(AssetManager.AssetType);

mID: AssetManager.AssetType = NullHandle,
mAssetManager: *AssetManager = undefined,

pub fn GetAsset(self: AssetHandle, comptime component_type: type, engine_context: *EngineContext) !*component_type {
    comptime {
        const Assets = @import("Assets.zig");
        const AssetMetaData = Assets.AssetMetaData;
        if (component_type == AssetMetaData) {
            @compileError("Cannot call AssetHandle.GetAsset with AssetMetaData\n");
        }

        const AssetsList = @import("Assets.zig").AssetsList;
        var is_type: bool = false;
        for (AssetsList) |asset_type| {
            if (component_type == asset_type) {
                is_type = true;
            }
        }
        if (is_type == false) {
            @compileError("Trying to call AssetHandle.GetAsset with a non-asset type!\n");
        }
    }
    return try engine_context.mAssetManager.GetAsset(component_type, self.mID);
}

pub fn ReleaseAsset(self: *AssetHandle) void {
    if (self.mID != NullHandle) {
        self.mAssetManager.ReleaseAssetHandleRef(self);
    }
}
