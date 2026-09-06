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

pub const EComponents = enum(16) {
    Texture2D = Texture2D.Ind,
    ScriptAsset = ScriptAsset.Ind,
    ShaderAsset = ShaderAsset.Ind,
    TextAsset = TextAsset.Ind,
    AssetMetaData = AssetMetaData.Ind,
    FileMetaData = FileMetaData.Ind,
    GenMetaData = GenMetaData.Ind,
    AudioAsset = AudioAsset.Ind,
};

pub const FileUpdateList = [_]type{
    Texture2D,
    ScriptAsset,
    ShaderAsset,
    TextAsset,
    AudioAsset,
};
