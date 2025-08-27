const std = @import("std");
const Entity = @import("Entity.zig");
const StaticAssetContext = @import("../Assets/AssetManager.zig");
const ScriptAsset = @import("../Assets/Assets.zig").ScriptAsset;
const ScriptComponent = @import("Components.zig").ScriptComponent;
const OnInputPressedScript = @import("Components.zig").OnInputPressedScript;
const OnUpdateInputScript = @import("Components.zig").OnUpdateInputScript;
const PathType = @import("../Assets/Assets.zig").FileMetaData.PathType;

pub fn AddScriptToEntity(entity: Entity, rel_path_script: []const u8, path_type: PathType) !void {
    var ecs = entity.mECSManagerRef;
    var new_script_handle = try StaticAssetContext.GetAssetHandleRef(rel_path_script, path_type);
    const script_asset = try new_script_handle.GetAsset(ScriptAsset);

    if (entity.GetComponent(ScriptComponent)) |script_component| {
        //entity already has a script so iterate until the end of the linked list

        const new_script_entity_id = try ecs.CreateEntity();
        const new_script_entity = Entity{ .mEntityID = new_script_entity_id, .mECSManagerRef = entity.mECSManagerRef };

        var iter_id = entity.mEntityID;
        var iter = script_component;
        while (iter.mNext != Entity.NullEntity) {
            iter_id = iter.mNext;
            iter = ecs.GetComponent(ScriptComponent, iter.mNext).?;
        }

        iter.mNext = new_script_entity.mEntityID;

        const new_script_component = ScriptComponent{
            .mFirst = iter.mFirst,
            .mNext = Entity.NullEntity,
            .mParent = iter.mParent,
            .mPrev = iter_id,
            .mScriptAssetHandle = new_script_handle,
        };

        switch (script_asset.mScriptType) {
            .OnInputPressed => {
                _ = try new_script_entity.AddComponent(ScriptComponent, new_script_component);
                _ = try new_script_entity.AddComponent(OnInputPressedScript, null);
            },
            .OnUpdateInput => {
                _ = try new_script_entity.AddComponent(ScriptComponent, new_script_component);
                _ = try new_script_entity.AddComponent(OnUpdateInputScript, null);
            },
            else => {},
        }
    } else {
        //entity does not have any scripts yet so add it directly to the entity
        const entity_new_script_component = ScriptComponent{
            .mFirst = entity.mEntityID,
            .mNext = Entity.NullEntity,
            .mParent = entity.mEntityID,
            .mPrev = Entity.NullEntity,
            .mScriptAssetHandle = new_script_handle,
        };

        switch (script_asset.mScriptType) {
            .OnInputPressed => {
                _ = try entity.AddComponent(ScriptComponent, entity_new_script_component);
                _ = try entity.AddComponent(OnInputPressedScript, null);
            },
            .OnUpdateInput => {
                _ = try entity.AddComponent(ScriptComponent, entity_new_script_component);
                _ = try entity.AddComponent(OnUpdateInputScript, null);
            },
            else => {},
        }
    }
}
