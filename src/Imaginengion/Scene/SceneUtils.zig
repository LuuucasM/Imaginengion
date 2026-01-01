const std = @import("std");
const SceneLayer = @import("SceneLayer.zig");
const PathType = @import("../Assets/Assets/FileMetaData.zig").PathType;
const EngineContext = @import("../Core//EngineContext.zig");
const Assets = @import("../Assets/Assets.zig");
const ScriptAsset = Assets.ScriptAsset;
const SceneComponents = @import("SceneComponents.zig");
const SceneScriptComponent = SceneComponents.ScriptComponent;
const OnSceneStartScript = SceneComponents.OnSceneStartScript;

pub fn AddScriptToScene(scene_layer: SceneLayer, script_asset_path: []const u8, path_type: PathType, engine_context: EngineContext) !void {
    var ecs = scene_layer.mECSManagerSCRef;
    var new_script_handle = try engine_context.mAssetManager.GetAssetHandleRef(script_asset_path, path_type);
    const script_asset = try new_script_handle.GetAsset(ScriptAsset);

    if (scene_layer.HasComponent(SceneScriptComponent) == true) {
        //entity already has a script so iterate until the end of the linked list

        const new_scene_id = try ecs.CreateEntity();
        const new_scene_layer = SceneLayer{ .mSceneID = new_scene_id, .mECSManagerGORef = scene_layer.mECSManagerGORef, .mECSManagerSCRef = scene_layer.mECSManagerSCRef };

        var iter_id = scene_layer.mSceneID;
        var iter = ecs.GetComponent(SceneScriptComponent, iter_id).?;
        while (iter.mNext != SceneLayer.NullScene) {
            iter_id = iter.mNext;
            iter = ecs.GetComponent(SceneScriptComponent, iter.mNext).?;
        }

        iter.mNext = new_scene_layer.mSceneID;

        const new_script_component = SceneScriptComponent{
            .mFirst = iter.mFirst,
            .mNext = SceneLayer.NullScene,
            .mParent = iter.mParent,
            .mPrev = iter_id,
            .mScriptAssetHandle = new_script_handle,
        };
        switch (script_asset.mScriptType) {
            .OnSceneStart => {
                _ = try new_scene_layer.AddComponent(SceneScriptComponent, new_script_component);
                _ = try new_scene_layer.AddComponent(OnSceneStartScript, null);
            },
            else => {},
        }
    } else {
        //scene does not have any scripts yet so add it directly to the scene_layer
        const entity_new_script_component = SceneScriptComponent{
            .mFirst = scene_layer.mSceneID,
            .mNext = SceneLayer.NullScene,
            .mParent = scene_layer.mSceneID,
            .mPrev = SceneLayer.NullScene,
            .mScriptAssetHandle = new_script_handle,
        };
        switch (script_asset.mScriptType) {
            .OnSceneStart => {
                _ = try scene_layer.AddComponent(SceneScriptComponent, entity_new_script_component);
                _ = try scene_layer.AddComponent(OnSceneStartScript, null);
            },
            else => {},
        }
    }
}
