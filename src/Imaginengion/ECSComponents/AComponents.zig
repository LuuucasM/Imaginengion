const ListInd = @import("../ECS/Components.zig").ListInd;
pub const AssetMetaData = @import("Asset/AssetMetaData.zig");
pub const FileMetaData = @import("Asset/FileMetaData.zig");
pub const GenMetaData = @import("Asset/GenMetaData.zig");
pub const ScriptAsset = @import("Asset/ScriptAsset.zig");
pub const ShaderAsset = @import("Asset/ShaderAsset.zig");
pub const Texture2D = @import("Asset/Texture2D.zig");
pub const TextAsset = @import("Asset/TextAsset.zig");
pub const AudioAsset = @import("Asset/AudioAsset.zig");
pub const EntityAsset = @import("Asset/EntityAsset.zig");

pub const ComponentsList = [_]type{
    Texture2D,
    ScriptAsset,
    ShaderAsset,
    TextAsset,
    AssetMetaData,
    FileMetaData,
    GenMetaData,
    AudioAsset,
    EntityAsset,
};

pub const EComponents = enum(16) {
    Texture2D = ListInd(&ComponentsList, Texture2D),
    ScriptAsset = ListInd(&ComponentsList, ScriptAsset),
    ShaderAsset = ListInd(&ComponentsList, ShaderAsset),
    TextAsset = ListInd(&ComponentsList, TextAsset),
    AssetMetaData = ListInd(&ComponentsList, AssetMetaData),
    FileMetaData = ListInd(&ComponentsList, FileMetaData),
    GenMetaData = ListInd(&ComponentsList, GenMetaData),
    AudioAsset = ListInd(&ComponentsList, AudioAsset),
    EntityAsset = ListInd(&ComponentsList, EntityAsset),
};

pub const FileUpdateList = [_]type{
    Texture2D,
    ScriptAsset,
    ShaderAsset,
    TextAsset,
    AudioAsset,
    EntityAsset,
};
