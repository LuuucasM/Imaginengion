pub const AssetMetaData = @import("Assets/AssetMetaData.zig");
pub const FileMetaData = @import("Assets/FileMetaData.zig");

pub const SceneAsset = @import("Assets/SceneAsset.zig");
pub const ScriptAsset = @import("Assets/ScriptAsset.zig");
pub const ShaderAsset = @import("Assets/ShaderAsset.zig");
pub const Texture2D = @import("Assets/Texture2D.zig");
pub const TextAsset = @import("Assets/TextAsset.zig");
pub const AudioAsset = @import("Assets/AudioAsset.zig");

pub const AssetsList = [_]type{
    Texture2D,
    ScriptAsset,
    ShaderAsset,
    SceneAsset,
    TextAsset,
    AssetMetaData,
    FileMetaData,
    AudioAsset,
};
