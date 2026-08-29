pub const AssetMetaData = @import("Asset/AssetMetaData.zig");
pub const FileMetaData = @import("Asset/FileMetaData.zig");
pub const GenMetaData = @import("Asset/GenMetaData.zig");
pub const ScriptAsset = @import("Asset/ScriptAsset.zig");
pub const ShaderAsset = @import("Asset/ShaderAsset.zig");
pub const Texture2D = @import("Asset/Texture2D.zig");
pub const TextAsset = @import("Asset/TextAsset.zig");
pub const AudioAsset = @import("Asset/AudioAsset.zig");

pub const ComponentsList = [_]type{
    Texture2D,
    ScriptAsset,
    ShaderAsset,
    TextAsset,
    AssetMetaData,
    FileMetaData,
    GenMetaData,
    AudioAsset,
};
