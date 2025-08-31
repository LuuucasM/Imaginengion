const std = @import("std");
const Entity = @import("Entity.zig");
const StaticAssetContext = @import("../Assets/AssetManager.zig");
const ScriptAsset = @import("../Assets/Assets.zig").ScriptAsset;

const EntityComponents = @import("Components.zig");
const ScriptComponent = EntityComponents.ScriptComponent;
const OnInputPressedScript = EntityComponents.OnInputPressedScript;
const OnUpdateInputScript = EntityComponents.OnUpdateInputScript;
const ParentComponent = EntityComponents.ParentComponent;
const ChildComponent = EntityComponents.ChildComponent;

const PathType = @import("../Assets/Assets.zig").FileMetaData.PathType;
const SceneLayer = @import("../Scene/SceneLayer.zig");

pub fn AddScriptToEntity(entity: Entity, rel_path_script: []const u8, path_type: PathType) !void {
    var ecs = entity.mECSManagerRef;
    var new_script_handle = try StaticAssetContext.GetAssetHandleRef(rel_path_script, path_type);
    const script_asset = try new_script_handle.GetAsset(ScriptAsset);

    // Create the script component with the asset handle
    const new_script_component = ScriptComponent{
        .mScriptAssetHandle = new_script_handle,
    };

    // Use ECSManager's AddComponent which handles the linked list logic
    const script_component_ptr = try ecs.AddComponent(ScriptComponent, entity.mEntityID, new_script_component);

    // Get the last entity in the script linked list
    // mFirst points to the first entity in the chain, and mPrev on that entity points to the last entity
    const first_script_entity_id = script_component_ptr.mFirst;
    const first_script_component = ecs.GetComponent(ScriptComponent, first_script_entity_id).?;
    const last_script_entity_id = first_script_component.mPrev;

    // Add the appropriate script type component based on the script asset
    switch (script_asset.mScriptType) {
        .OnInputPressed => {
            _ = try ecs.AddComponent(OnInputPressedScript, last_script_entity_id, null);
        },
        .OnUpdateInput => {
            _ = try ecs.AddComponent(OnUpdateInputScript, last_script_entity_id, null);
        },
        else => {},
    }
}

pub fn AddChildEntity(parent_entity: Entity, scene_layer: SceneLayer) !void {
    const new_entity = try scene_layer.CreateEntity();

    if (parent_entity.HasComponent(ParentComponent)) {
        // Parent already has children, so add to existing linked list
        const parent_component = parent_entity.GetComponent(ParentComponent).?;

        const first_child_entity_id = parent_component.mFirstChild;
        const first_child_entity = Entity{ .mEntityID = first_child_entity_id, .mECSManagerRef = parent_entity.mECSManagerRef };
        const first_child_component = first_child_entity.GetComponent(ChildComponent).?;

        const last_child_entity_id = first_child_component.mPrev;
        const last_child_entity = Entity{ .mEntityID = last_child_entity_id, .mECSManagerRef = parent_entity.mECSManagerRef };
        const last_child_component = last_child_entity.GetComponent(ChildComponent).?;

        // Create child component for the new entity
        const new_child_component = ChildComponent{
            .mFirst = first_child_entity_id,
            .mNext = first_child_entity_id, // Last child points back to first child
            .mParent = parent_entity.mEntityID,
            .mPrev = last_child_entity_id,
        };
        _ = try new_entity.AddComponent(ChildComponent, new_child_component);

        // Update the last child to point to the new child
        last_child_component.mNext = new_entity.mEntityID;

        // Update the first child's mPrev to point to the new last child
        first_child_component.mPrev = new_entity.mEntityID;
    } else {
        // Parent has no children yet, so this is the first one
        const new_parent_component = ParentComponent{ .mFirstChild = new_entity.mEntityID };
        _ = try parent_entity.AddComponent(ParentComponent, new_parent_component);

        const new_child_component = ChildComponent{
            .mFirst = new_entity.mEntityID,
            .mNext = new_entity.mEntityID,
            .mParent = parent_entity.mEntityID,
            .mPrev = new_entity.mEntityID,
        };
        _ = try new_entity.AddComponent(ChildComponent, new_child_component);
    }
}
