//! This file exists as a location to group together all the functions that run
//! scripts rather than cluddering up other engine files like scene manager or something
const std = @import("std");
const StaticEngineContext = @import("../Core/EngineContext.zig");
const EngineContext = StaticEngineContext.EngineContext;
const SceneManager = @import("../Scene/SceneManager.zig");
const SceneType = SceneManager.SceneType;
const ECSManagerScenes = SceneManager.ECSManagerScenes;
const ECSManagerGameObj = SceneManager.ECSManagerGameObj;
const EntityType = SceneManager.EntityType;
const SceneLayer = @import("../Scene/SceneLayer.zig");
const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;

const GameEvent = @import("../Events/GameEvent.zig");
const SystemEvent = @import("../Events/SystemEvent.zig");
const InputPressedEvent = SystemEvent.InputPressedEvent;

const EntityComponents = @import("../GameObjects/Components.zig");
const ScriptComponent = EntityComponents.ScriptComponent;
const OnInputPressedScript = EntityComponents.OnInputPressedScript;
const OnUpdateInputScript = EntityComponents.OnUpdateInputScript;
const EntitySceneComponent = EntityComponents.SceneIDComponent;
const CameraComponent = EntityComponents.CameraComponent;

const SceneComponents = @import("../Scene/SceneComponents.zig");
const StackPosComponent = SceneComponents.StackPosComponent;
const OnSceneStartScript = SceneComponents.OnSceneStartScript;

const Assets = @import("../Assets/Assets.zig");
const ScriptAsset = Assets.ScriptAsset;

const Entity = @import("../GameObjects/Entity.zig");

pub fn RunEntityScript(scene_manager: *SceneManager, comptime script_type: type, args: anytype) !bool {
    comptime {
        if (script_type != OnInputPressedScript or script_type != OnUpdateInputScript) {
            @compileError("Cannot use this type as a Entity Script type!");
        }
    }
    //TODO: change to new scene system
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const ecs_manager_go = scene_manager.mECSManagerGO;

    const scene_stack_scenes = try scene_manager.mECSManagerSC.GetGroup(GroupQuery{ .Component = StackPosComponent }, allocator);
    std.sort.insertion(SceneType, scene_stack_scenes.items, scene_manager.mECSManagerSC, SceneManager.SortScenesFunc);

    var cont_bool = true;
    for (scene_stack_scenes.items) |scene_id| {
        if (cont_bool == false) break;

        var scene_scripts = try ecs_manager_go.GetGroup(GroupQuery{ .Component = script_type }, allocator);
        scene_manager.FilterScriptsByScene(&scene_scripts, scene_id);

        for (scene_scripts.items) |script_id| {
            const script_component = ecs_manager_go.GetComponent(ScriptComponent, script_id);
            const script_asset = try script_component.mScriptAssetHandle.GetAsset(ScriptAsset);
            const run_func = script_asset.mLib.lookup(script_type.RunFuncSig, "Run").?;

            var entity = Entity{ .mEntityID = script_component.mParent, .mECSManagerRef = &scene_manager.mECSManagerGO };

            const combined_args = .{ StaticEngineContext.GetInstance(), &allocator, &entity } ++ args;

            cont_bool = cont_bool and @call(.auto, run_func, combined_args);
        }
    }
    return cont_bool;
}

pub fn RunSceneScript(scene_manager: *SceneManager, comptime script_type: type, args: anytype) !bool {
    comptime {
        if (script_type != OnSceneStartScript) {
            @compileError("Cannot use this type as a Scene Script type!");
        }
    }
    //TODO: change to new scene system
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const ecs_manager_sc = scene_manager.mECSManagerSC;

    const scene_scripts = try ecs_manager_sc.GetGroup(GroupQuery{ .Component = script_type }, allocator);
    FilterInSceneStack(ecs_manager_sc, scene_scripts);

    for (scene_scripts.items) |scene_id| {
        const script_component = ecs_manager_sc.GetComponent(ScriptComponent, scene_id);
        const script_asset = try script_component.mScriptAssetHandle.GetAsset(ScriptAsset);
        const run_func = script_asset.mLib.lookup(script_type.RunFuncSig, "Run").?;

        var scene_layer = SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = scene_manager.mECSManagerGO, .mECSManagerSCRef = scene_manager.mECSManagerSC };

        const combined_args = .{ StaticEngineContext.GetInstance(), &allocator, &scene_layer } ++ args;

        _ = @call(.auto, run_func, combined_args);
    }

    return true;
}
pub fn RunEntityScriptEditor(editor_scene_layer: *SceneLayer, editor_window_in_focus: bool, comptime script_type: type, args: anytype) !bool {
    comptime {
        if (script_type != OnInputPressedScript or script_type != OnUpdateInputScript) {
            @compileError("Cannot use this type as a Entity Script type!");
        }
    }
    //TODO change to new scene system
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var ecs_manager_go = editor_scene_layer.mECSManagerGORef;

    var input_pressed_entities = if (editor_window_in_focus == true) try ecs_manager_go.GetGroup(.{ .Component = script_type }, allocator) else try ecs_manager_go.GetGroup(.{ .Not = .{ .mFirst = GroupQuery{ .Component = script_type }, .mSecond = GroupQuery{ .Component = CameraComponent } } }, allocator);
    FilterByScene(editor_scene_layer.mECSManagerGORef, &input_pressed_entities, editor_scene_layer.mSceneID);

    for (input_pressed_entities.items) |script_id| {
        const script_component = ecs_manager_go.GetComponent(ScriptComponent, script_id);
        const script_asset = try script_component.mScriptAssetHandle.GetAsset(ScriptAsset);
        const run_func = script_asset.mLib.lookup(script_type.RunFuncSig, "Run").?;

        var entity = Entity{ .mEntityID = script_component.mParent, .mECSManagerRef = editor_scene_layer.mECSManagerGORef };

        const combined_args = .{ StaticEngineContext.GetInstance(), &allocator, &entity } ++ args;

        _ = @call(.auto, run_func, combined_args);
    }

    return true;
}

pub fn RunSceneScriptEditor(editor_scene_layer: *SceneLayer, editor_window_in_focus: bool, comptime script_type: type, args: anytype) !bool {
    comptime {
        if (script_type != OnSceneStartScript) {
            @compileError("Cannot use this type as a Scene Script type!");
        }
    }
    //TODO: change to new scene system
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const ecs_manager_sc = editor_scene_layer.mECSManagerSCRef;

    const scene_scripts = try ecs_manager_sc.GetGroup(GroupQuery{ .Component = script_type }, allocator);
    FilterIsInScene(ecs_manager_sc, scene_scripts, editor_scene_layer.mSceneID);

    for (scene_scripts.items) |scene_id| {
        const script_component = ecs_manager_sc.GetComponent(ScriptComponent, scene_id);
        const script_asset = try script_component.mScriptAssetHandle.GetAsset(ScriptAsset);
        const run_func = script_asset.mLib.lookup(script_type.RunFuncSig, "Run").?;

        var scene_layer = SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = scene_manager.mECSManagerGO, .mECSManagerSCRef = scene_manager.mECSManagerSC };

        const combined_args = .{ StaticEngineContext.GetInstance(), &allocator, &scene_layer } ++ args;

        _ = @call(.auto, run_func, combined_args);
    }

    return true;
}

pub fn FilterByScene(ecs_manager_go: *ECSManagerGameObj, result_list: *std.ArrayList(EntityType), scene_id: SceneType) void {
    if (result_list.items.len == 0) return;

    var end_index: usize = result_list.items.len;
    var i: usize = 0;

    while (i < end_index) {
        const entity_scene_component = ecs_manager_go.GetComponent(EntitySceneComponent, result_list.items[i]);
        if (entity_scene_component.SceneID != scene_id) {
            result_list.items[i] = result_list.items[end_index - 1];
            end_index -= 1;
        } else {
            i += 1;
        }
    }

    result_list.shrinkAndFree(end_index);
}

pub fn FilterInSceneStack(ecs_manager_sc: *ECSManagerScenes, result_list: *std.ArrayList(SceneType)) void {
    if (result_list.items.len == 0) return;

    var end_index: usize = result_list.items.len;
    var i: usize = 0;

    while (i < end_index) {
        const script_component = ecs_manager_sc.GetComponent(ScriptComponent, result_list.items[i]);
        if (ecs_manager_sc.HasComponent(StackPosComponent, script_component.mParent) == false) {
            result_list.items[i] = result_list.items[end_index - 1];
            end_index -= 1;
        } else {
            i += 1;
        }
    }

    result_list.shrinkAndFree(end_index);
}

pub fn FilterIsInScene(ecs_manager_sc: *ECSManagerScenes, result_list: *std.ArrayList(SceneType), scene_id: SceneType) void {
    if (result_list.items.len == 0) return;

    var end_index: usize = result_list.items.len;
    var i: usize = 0;

    while (i < end_index) {
        const script_component = ecs_manager_sc.GetComponent(ScriptComponent, result_list.items[i]);
        if (script_component.mParent != scene_id) {
            result_list.items[i] = result_list.items[end_index - 1];
            end_index -= 1;
        } else {
            i += 1;
        }
    }

    result_list.shrinkAndFree(end_index);
}
