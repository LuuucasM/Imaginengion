//! This file exists as a location to group together all the functions that run
//! scripts rather than cluddering up other engine files like scene manager or something
const std = @import("std");
const StaticEngineContext = @import("../Core/EngineContext.zig");
const EngineContext = StaticEngineContext.EngineContext;
const SceneManager = @import("../Scene/SceneManager.zig");
const EntityType = SceneManager.EntityType;
const SceneLayer = @import("../Scene/SceneLayer.zig");
const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;

const GameEvent = @import("../Events/GameEvent.zig");
const SystemEvent = @import("../Events/SystemEvent.zig");
const InputPressedEvent = SystemEvent.InputPressedEvent;

const Components = @import("../GameObjects/Components.zig");
const ScriptComponent = Components.ScriptComponent;
const OnInputPressedScript = Components.OnInputPressedScript;
const OnUpdateInputScript = Components.OnUpdateInputScript;
const SceneIDComponent = Components.SceneIDComponent;
const CameraComponent = Components.CameraComponent;

const Assets = @import("../Assets/Assets.zig");
const ScriptAsset = Assets.ScriptAsset;

const Entity = @import("../GameObjects/Entity.zig");

pub fn RunScript(scene_manager: *SceneManager, comptime script_type: type, args: anytype) !bool {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const ecs_manager = scene_manager.mECSManager;

    const input_pressed_entities = try scene_manager.mECSManager.GetGroup(.{ .Component = script_type }, allocator);

    var iter = std.mem.reverseIterator(scene_manager.mSceneStack.items);
    var cont_bool = true;
    while (iter.next()) |*scene_layer| {
        if (cont_bool == false) break;

        var scene_scripts = try std.ArrayList(EntityType).initCapacity(allocator, scene_layer.mEntityList.items.len);
        try scene_scripts.appendSlice(scene_layer.mEntityList.items);
        try ecs_manager.EntityListIntersection(&scene_scripts, input_pressed_entities, allocator);

        for (scene_scripts.items) |script_id| {
            const script_component = ecs_manager.GetComponent(ScriptComponent, script_id);
            const script_asset = try script_component.mScriptAssetHandle.GetAsset(ScriptAsset);
            const run_func = script_asset.mLib.lookup(script_type.RunFuncSig, "Run").?;

            var entity = Entity{ .mEntityID = script_component.mParent, .mSceneLayerRef = @constCast(scene_layer) };

            const combined_args = .{ StaticEngineContext.GetInstance(), &allocator, &entity } ++ args;

            cont_bool = cont_bool and @call(.auto, run_func, combined_args);
        }
    }
    return cont_bool;
}
pub fn RunScriptEditor(editor_scene_layer: *SceneLayer, editor_window_in_focus: bool, comptime script_type: type, args: anytype) !bool {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var ecs_manager = editor_scene_layer.mECSManagerRef;

    const input_pressed_entities = if (editor_window_in_focus == true) try ecs_manager.GetGroup(.{ .Component = script_type }, allocator) else try ecs_manager.GetGroup(.{ .Not = .{ .mFirst = GroupQuery{ .Component = script_type }, .mSecond = GroupQuery{ .Component = CameraComponent } } }, allocator);

    var scene_scripts = try std.ArrayList(EntityType).initCapacity(allocator, editor_scene_layer.mEntityList.items.len);
    try scene_scripts.appendSlice(editor_scene_layer.mEntityList.items);
    try ecs_manager.EntityListIntersection(&scene_scripts, input_pressed_entities, allocator);

    for (scene_scripts.items) |script_id| {
        const script_component = ecs_manager.GetComponent(ScriptComponent, script_id);
        const script_asset = try script_component.mScriptAssetHandle.GetAsset(ScriptAsset);
        const run_func = script_asset.mLib.lookup(script_type.RunFuncSig, "Run").?;

        var entity = Entity{ .mEntityID = script_component.mParent, .mSceneLayerRef = @constCast(editor_scene_layer) };

        const combined_args = .{ StaticEngineContext.GetInstance(), &allocator, &entity } ++ args;

        _ = @call(.auto, run_func, combined_args);
    }

    return true;
}
