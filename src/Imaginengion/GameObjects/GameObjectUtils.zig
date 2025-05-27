const std = @import("std");
const Entity = @import("Entity.zig");
const StaticAssetContext = @import("../Assets/AssetManager.zig");
const ScriptAsset = @import("../Assets/Assets.zig").ScriptAsset;
const ScriptComponent = @import("Components.zig").ScriptComponent;
const OnInputPressedScript = @import("Components.zig").OnInputPressedScript;
const OnUpdateInputScript = @import("Components.zig").OnUpdateInputScript;
const PathType = @import("../Assets/Assets.zig").FileMetaData.PathType;
const EntityType = @import("../Scene/SceneManager.zig").EntityType;

pub fn AddScriptToEntity(entity: Entity, script_asset_path: []const u8, path_type: PathType) !void {
    var ecs = entity.mECSManagerRef;
    var new_script_handle = try StaticAssetContext.GetAssetHandleRef(script_asset_path, path_type);
    const script_asset = try new_script_handle.GetAsset(ScriptAsset);
    const new_script_entity = try ecs.CreateEntity();

    if (entity.HasComponent(ScriptComponent) == true) {
        //entity already has a script so iterate until the end of the linked list
        var iter_id = entity.mEntityID;
        var iter = ecs.GetComponent(ScriptComponent, iter_id);
        while (iter.mNext != Entity.NullEntity) {
            iter_id = iter.mNext;
            iter = ecs.GetComponent(ScriptComponent, iter.mNext);
        }

        iter.mNext = new_script_entity;

        const new_script_component = ScriptComponent{
            .mFirst = iter.mFirst,
            .mNext = Entity.NullEntity,
            .mParent = iter.mParent,
            .mPrev = iter_id,
            .mScriptAssetHandle = new_script_handle,
        };

        _ = try ecs.AddComponent(ScriptComponent, new_script_entity, new_script_component);

        _ = switch (script_asset.mScriptType) {
            .OnInputPressed => try ecs.AddComponent(OnInputPressedScript, new_script_entity, null),
            .OnUpdateInput => try ecs.AddComponent(OnUpdateInputScript, new_script_entity, null),
        };
    } else {
        //add new script component to entity
        const entity_new_script_component = ScriptComponent{
            .mFirst = entity.mEntityID,
            .mNext = Entity.NullEntity,
            .mParent = entity.mEntityID,
            .mPrev = Entity.NullEntity,
            .mScriptAssetHandle = new_script_handle,
        };

        _ = try entity.AddComponent(ScriptComponent, entity_new_script_component);

        _ = switch (script_asset.mScriptType) {
            .OnInputPressed => try entity.AddComponent(OnInputPressedScript, null),
            .OnUpdateInput => try entity.AddComponent(OnUpdateInputScript, null),
        };
    }
}
