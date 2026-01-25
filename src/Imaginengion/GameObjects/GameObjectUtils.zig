const std = @import("std");
const Entity = @import("Entity.zig");
const ScriptAsset = @import("../Assets/Assets.zig").ScriptAsset;
const EngineContext = @import("../Core/EngineContext.zig");
const EntityComponents = @import("Components.zig");
const ScriptComponent = EntityComponents.ScriptComponent;
const OnInputPressedScript = EntityComponents.OnInputPressedScript;
const OnUpdateScript = EntityComponents.OnUpdateScript;
const TransformComponent = EntityComponents.TransformComponent;

const PathType = @import("../Assets/Assets.zig").FileMetaData.PathType;
const SceneLayer = @import("../Scene/SceneLayer.zig");

pub fn AddScriptToEntity(engine_context: *EngineContext, entity: Entity, rel_path_script: []const u8, path_type: PathType) !void {
    var new_script_handle = try engine_context.mAssetManager.GetAssetHandleRef(engine_context.EngineAllocator(), rel_path_script, path_type);
    const script_asset = try new_script_handle.GetAsset(engine_context, ScriptAsset);

    // Create the script component with the asset handle
    const new_script_component = ScriptComponent{
        .mScriptAssetHandle = new_script_handle,
    };

    const new_script_entity = try entity.AddChild(.Script);

    _ = try new_script_entity.AddComponent(ScriptComponent, new_script_component);

    // Add the appropriate script type component based on the script asset
    switch (script_asset.mScriptType) {
        .EntityInputPressed => {
            _ = try new_script_entity.AddComponent(OnInputPressedScript, null);
        },
        .EntityOnUpdate => {
            _ = try new_script_entity.AddComponent(OnUpdateScript, null);
        },
        else => {},
    }
}
