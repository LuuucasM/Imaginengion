const ListInd = @import("../ECS/Components.zig").ListInd;
pub const AssetMetaData = @import("Asset/AssetMetaData.zig");
pub const FileMetaData = @import("Asset/FileMetaData.zig");
pub const GenMetaData = @import("Asset/GenMetaData.zig");
pub const ScriptAsset = @import("Asset/ScriptAsset.zig");
pub const ShaderAsset = @import("Asset/ShaderAsset.zig");
pub const Texture2D = @import("Asset/Texture2D.zig");
pub const TextAsset = @import("Asset/TextAsset.zig");
pub const AudioAsset = @import("Asset/AudioAsset.zig");

//the ECS objects loaded from their files, see ObjectAsset.zig
const ObjectAsset = @import("Asset/ObjectAsset.zig").ObjectAsset;
pub const EntityAsset = ObjectAsset(@import("../ECSObjects/Entity.zig"), "EntityAsset");
pub const SceneAsset = ObjectAsset(@import("../ECSObjects/Scene.zig"), "SceneAsset");
pub const PlayerAsset = ObjectAsset(@import("../ECSObjects/Player.zig"), "PlayerAsset");
pub const GCAsset = ObjectAsset(@import("../ECSObjects/GameContext.zig"), "GCAsset");

/// The asset an object of type obj_t is loaded as, e.g. Entity -> EntityAsset
pub fn ObjectAssetFor(comptime obj_t: type) type {
    const asset_types = [_]type{ EntityAsset, SceneAsset, PlayerAsset, GCAsset };
    inline for (asset_types) |asset_t| {
        if (@FieldType(asset_t, "mObject") == obj_t) return asset_t;
    }
    @compileError(@typeName(obj_t) ++ " has no asset type");
}

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
    SceneAsset,
    PlayerAsset,
    GCAsset,
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
    SceneAsset = ListInd(&ComponentsList, SceneAsset),
    PlayerAsset = ListInd(&ComponentsList, PlayerAsset),
    GCAsset = ListInd(&ComponentsList, GCAsset),
};

pub const FileUpdateList = [_]type{
    Texture2D,
    ScriptAsset,
    ShaderAsset,
    TextAsset,
    AudioAsset,
    EntityAsset,
    SceneAsset,
    PlayerAsset,
    GCAsset,
};
