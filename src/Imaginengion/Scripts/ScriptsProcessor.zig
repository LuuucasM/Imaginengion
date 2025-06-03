//! This file exists as a location to group together all the functions that run
//! scripts rather than cluddering up other engine files like scene manager or something
const std = @import("std");
const StaticEngineContext = @import("../Core/EngineContext.zig");
const EngineContext = StaticEngineContext.EngineContext;
const SceneManager = @import("../Scene/SceneManager.zig");
const SceneType = SceneManager.SceneType;
const ECSManagerScenes = SceneManager.ECSManagerScenes;
const ECSManagerGameObj = SceneManager.ECSManagerGameObj;
const SceneLayer = @import("../Scene/SceneLayer.zig");
const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;

const GameEvent = @import("../Events/GameEvent.zig");
const SystemEvent = @import("../Events/SystemEvent.zig");
const InputPressedEvent = SystemEvent.InputPressedEvent;

const EntityComponents = @import("../GameObjects/Components.zig");
const EntityScriptComponent = EntityComponents.ScriptComponent;
const OnInputPressedScript = EntityComponents.OnInputPressedScript;
const OnUpdateInputScript = EntityComponents.OnUpdateInputScript;
const EntitySceneComponent = EntityComponents.SceneIDComponent;
const CameraComponent = EntityComponents.CameraComponent;

const SceneComponents = @import("../Scene/SceneComponents.zig");
const SceneScriptComponent = SceneComponents.ScriptComponent;
const StackPosComponent = SceneComponents.StackPosComponent;
const OnSceneStartScript = SceneComponents.OnSceneStartScript;

const Assets = @import("../Assets/Assets.zig");
const ScriptAsset = Assets.ScriptAsset;

const Entity = @import("../GameObjects/Entity.zig");

pub fn RunEntityScript(scene_manager: *SceneManager, comptime script_type: type, args: anytype) !bool {
    comptime {
        if (script_type != OnInputPressedScript and
            script_type != OnUpdateInputScript)
        {
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
        scene_manager.FilterEntityScriptsByScene(&scene_scripts, scene_id);

        for (scene_scripts.items) |script_id| {
            const script_component = ecs_manager_go.GetComponent(EntityScriptComponent, script_id);
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

    const scene_stack_scenes = try scene_manager.mECSManagerSC.GetGroup(GroupQuery{ .Component = StackPosComponent }, allocator);
    std.sort.insertion(SceneType, scene_stack_scenes.items, scene_manager.mECSManagerSC, SceneManager.SortScenesFunc);

    var cont_bool = true;
    for (scene_stack_scenes.items) |scene_id| {
        if (cont_bool == false) break;

        var scene_scripts = try ecs_manager_sc.GetGroup(GroupQuery{ .Component = script_type }, allocator);
        scene_manager.FilterSceneScriptsByScene(&scene_scripts, scene_id);

        for (scene_scripts.items) |script_id| {
            const script_component = ecs_manager_sc.GetComponent(SceneScriptComponent, script_id);
            const script_asset = try script_component.mScriptAssetHandle.GetAsset(ScriptAsset);
            const run_func = script_asset.mLib.lookup(script_type.RunFuncSig, "Run").?;

            var scene = SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &scene_manager.mECSManagerGO, .mECSManagerSCRef = &scene_manager.mECSManagerSC };

            const combined_args = .{ StaticEngineContext.GetInstance(), &allocator, &scene } ++ args;

            cont_bool = cont_bool and @call(.auto, run_func, combined_args);
        }
    }
    return cont_bool;
}
pub fn RunEntityScriptEditor(scene_manager: *SceneManager, comptime script_type: type, args: anytype, editor_scene_layer: *SceneLayer) !bool {
    comptime {
        if (script_type != OnInputPressedScript and
            script_type != OnUpdateInputScript)
        {
            @compileError("Cannot use this type as a Entity Script type!");
        }
    }
    //TODO: change to new scene system
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const ecs_manager_go = scene_manager.mECSManagerGO;

    var scene_scripts = try ecs_manager_go.GetGroup(GroupQuery{ .Component = script_type }, allocator);
    scene_manager.FilterEntityScriptsByScene(&scene_scripts, editor_scene_layer.mSceneID);

    for (scene_scripts.items) |script_id| {
        const script_component = ecs_manager_go.GetComponent(EntityScriptComponent, script_id);
        const script_asset = try script_component.mScriptAssetHandle.GetAsset(ScriptAsset);
        const run_func = script_asset.mLib.lookup(script_type.RunFuncSig, "Run").?;

        var entity = Entity{ .mEntityID = script_component.mParent, .mECSManagerRef = &scene_manager.mECSManagerGO };

        const combined_args = .{ StaticEngineContext.GetInstance(), &allocator, &entity } ++ args;

        _ = @call(.auto, run_func, combined_args);
    }
    return true;
}

pub fn RunSceneScriptEditor(scene_manager: *SceneManager, comptime script_type: type, args: anytype, editor_scene_layer: *SceneLayer) !bool {
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

    var scene_scripts = try ecs_manager_sc.GetGroup(GroupQuery{ .Component = script_type }, allocator);
    scene_manager.FilterSceneScriptsByScene(&scene_scripts, editor_scene_layer.mSceneID);

    for (scene_scripts.items) |script_id| {
        const script_component = ecs_manager_sc.GetComponent(SceneScriptComponent, script_id);
        const script_asset = try script_component.mScriptAssetHandle.GetAsset(ScriptAsset);
        const run_func = script_asset.mLib.lookup(script_type.RunFuncSig, "Run").?;

        var scene = SceneLayer{ .mSceneID = editor_scene_layer.mSceneID, .mECSManagerGORef = &scene_manager.mECSManagerGO, .mECSManagerSCRef = &scene_manager.mECSManagerSC };

        const combined_args = .{ StaticEngineContext.GetInstance(), &allocator, &scene } ++ args;

        _ = @call(.auto, run_func, combined_args);
    }
    return true;
}
