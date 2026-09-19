const AssetHandle = @import("../ECSObjects/AssetHandle.zig");
const EventResult = @import("EventManager.zig").EventResult;
const EngineContext = @import("../Core/EngineContext.zig");
pub const AssetComponents = @import("../ECSComponents/AComponents.zig");

pub const EventCategories = enum(u8) {
    EndOfFrame,
};

pub const EventT = union(enum) {
    Default: DefaultEvent,
    ToDestroyAsset: ToDestroyAssetEvent,
    FileUpdate: FileUpdateEvent,

    pub const DefaultEvent = struct {};

    pub const ToDestroyAssetEvent = struct {
        mAssetID: AssetHandle.Type,
    };
    pub const FileUpdateEvent = struct {
        mAssetID: AssetHandle.Type,
    };
};
