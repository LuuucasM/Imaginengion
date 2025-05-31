const SceneLayer = @import("SceneLayer.zig");
const PathType = @import("../Assets/Assets/FileMetaData.zig").PathType;
const StaticAssetContext = @import("../Assets/AssetManager.zig");
const Assets = @import("../Assets/Assets.zig");
const ScriptAsset = Assets.ScriptAsset;
const SceneComponents = @import("SceneComponents.zig");
const SceneScriptComponent = SceneComponents.ScriptComponent;
const OnSceneStartScript = SceneComponents.OnSceneStartScript;

pub fn AddScriptToScene(scene_layer: SceneLayer, script_asset_path: []const u8, path_type: PathType) !void {
    var ecs = scene_layer.mECSManagerSCRef;
    var new_script_handle = try StaticAssetContext.GetAssetHandleRef(script_asset_path, path_type);
    const script_asset = try new_script_handle.GetAsset(ScriptAsset);
    const new_script_entity = try ecs.CreateEntity();

    if (scene_layer.HasComponent(SceneScriptComponent) == true) {
        //entity already has a script so iterate until the end of the linked list
        var iter_id = scene_layer.mSceneID;
        var iter = ecs.GetComponent(SceneScriptComponent, iter_id);
        while (iter.mNext != SceneLayer.NullScene) {
            iter_id = iter.mNext;
            iter = ecs.GetComponent(SceneScriptComponent, iter.mNext);
        }

        iter.mNext = new_script_entity;

        const new_script_component = SceneScriptComponent{
            .mFirst = iter.mFirst,
            .mNext = SceneLayer.NullScene,
            .mParent = iter.mParent,
            .mPrev = iter_id,
            .mScriptAssetHandle = new_script_handle,
        };

        _ = try ecs.AddComponent(SceneScriptComponent, new_script_entity, new_script_component);

        _ = switch (script_asset.mScriptType) {
            .OnSceneStart => try ecs.AddComponent(OnSceneStartScript, new_script_entity, null),
            else => {},
        };
    } else {
        //add new script component to entity
        const entity_new_script_component = SceneScriptComponent{
            .mFirst = scene_layer.mSceneID,
            .mNext = SceneLayer.NullScene,
            .mParent = scene_layer.mSceneID,
            .mPrev = SceneLayer.NullScene,
            .mScriptAssetHandle = new_script_handle,
        };

        _ = try scene_layer.AddComponent(SceneScriptComponent, entity_new_script_component);

        _ = switch (script_asset.mScriptType) {
            .OnSceneStart => try scene_layer.AddComponent(OnSceneStartScript, null),
            else => {},
        };
    }
}
