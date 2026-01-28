const std = @import("std");
const SceneLayer = @import("SceneLayer.zig");
const PathType = @import("../Assets/Assets/FileMetaData.zig").PathType;
const EngineContext = @import("../Core//EngineContext.zig");
const Assets = @import("../Assets/Assets.zig");
const ScriptAsset = Assets.ScriptAsset;
const SceneComponents = @import("SceneComponents.zig");
const SceneScriptComponent = SceneComponents.ScriptComponent;
const OnSceneStartScript = SceneComponents.OnSceneStartScript;
const SceneParentComponent = @import("../ECS/Components.zig").ParentComponent(SceneLayer.Type);
const SceneChildComponent = @import("../ECS/Components.zig").ChildComponent(SceneLayer.Type);

pub fn AddScriptToScene(engine_context: *EngineContext, scene_layer: SceneLayer, script_asset_path: []const u8, path_type: PathType) !void {
    var new_script_handle = try engine_context.mAssetManager.GetAssetHandleRef(engine_context.EngineAllocator(), script_asset_path, path_type);
    const script_asset = try new_script_handle.GetAsset(engine_context, ScriptAsset);

    std.debug.assert(script_asset.mScriptType == .SceneSceneStart);

    const new_script_component = SceneScriptComponent{
        .mScriptAssetHandle = new_script_handle,
    };

    const new_script_entity = try scene_layer.AddChild(engine_context, .Script);

    _ = try new_script_entity.AddComponent(SceneScriptComponent, new_script_component);

    _ = switch (script_asset.mScriptType) {
        .SceneSceneStart => try new_script_entity.AddComponent(OnSceneStartScript, null),
        else => @panic("This shouldnt happen!"),
    };
}
