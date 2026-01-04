const std = @import("std");
const Entity = @import("Entity.zig");
const ScriptAsset = @import("../Assets/Assets.zig").ScriptAsset;
const EngineContext = @import("../Core/EngineContext.zig");
const EntityComponents = @import("Components.zig");
const ScriptComponent = EntityComponents.ScriptComponent;
const OnInputPressedScript = EntityComponents.OnInputPressedScript;
const OnUpdateScript = EntityComponents.OnUpdateScript;

const PathType = @import("../Assets/Assets.zig").FileMetaData.PathType;
const SceneLayer = @import("../Scene/SceneLayer.zig");

pub fn AddScriptToEntity(entity: Entity, rel_path_script: []const u8, path_type: PathType, engine_context: *EngineContext) !void {
    var ecs = entity.mECSManagerRef;
    var new_script_handle = try engine_context.mAssetManager.GetAssetHandleRef(engine_context.mEngineAllocator, rel_path_script, path_type);
    const script_asset = try new_script_handle.GetAsset(engine_context, ScriptAsset);

    // Create the script component with the asset handle
    const new_script_component = ScriptComponent{
        .mScriptAssetHandle = new_script_handle,
    };

    // Use ECSManager's AddComponent which handles the linked list logic
    const script_component_ptr = try entity.AddComponent(ScriptComponent, new_script_component);

    // Get the entity_id for the newest script added
    const prev_script_entity_id = script_component_ptr.mPrev;
    const prev_script_component = ecs.GetComponent(ScriptComponent, prev_script_entity_id).?;
    const last_script_entity_id = prev_script_component.mNext;

    std.debug.assert(ecs.GetComponent(ScriptComponent, last_script_entity_id).? == script_component_ptr);

    // Add the appropriate script type component based on the script asset
    switch (script_asset.mScriptType) {
        .EntityInputPressed => {
            _ = try ecs.AddComponent(OnInputPressedScript, last_script_entity_id, null);
        },
        .EntityOnUpdate => {
            _ = try ecs.AddComponent(OnUpdateScript, last_script_entity_id, null);
        },
        else => {},
    }
}
