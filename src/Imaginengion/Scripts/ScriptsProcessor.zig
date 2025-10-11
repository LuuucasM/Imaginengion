//! This file exists as a location to group together all the functions that run
//! scripts rather than cluddering up other engine files like scene manager or something
const std = @import("std");
const StaticEngineContext = @import("../Core/EngineContext.zig");
const EngineContext = StaticEngineContext.EngineContext;
const SceneManager = @import("../Scene/SceneManager.zig");
const SceneType = SceneLayer.Type;
const ECSManagerScenes = SceneManager.ECSManagerScenes;
const ECSManagerGameObj = SceneManager.ECSManagerGameObj;
const SceneLayer = @import("../Scene/SceneLayer.zig");
const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;

const GameEvent = @import("../Events/GameEvent.zig");
const SystemEvent = @import("../Events/SystemEvent.zig");
const InputPressedEvent = SystemEvent.InputPressedEvent;

const EntityScriptList = @import("../GameObjects/Components.zig").ScriptList;
const EntityComponents = @import("../GameObjects/Components.zig");
const EntityScriptComponent = EntityComponents.ScriptComponent;
const OnInputPressedScript = EntityComponents.OnInputPressedScript;
const OnUpdateInputScript = EntityComponents.OnUpdateInputScript;
const EntitySceneComponent = EntityComponents.SceneIDComponent;
const CameraComponent = EntityComponents.CameraComponent;

const SceneScriptList = @import("../Scene/SceneComponents.zig").ScriptList;
const SceneComponents = @import("../Scene/SceneComponents.zig");
const SceneScriptComponent = SceneComponents.ScriptComponent;
const StackPosComponent = SceneComponents.StackPosComponent;
const OnSceneStartScript = SceneComponents.OnSceneStartScript;

const AssetsList = @import("../Assets/Assets.zig").AssetsList;
const Assets = @import("../Assets/Assets.zig");
const ScriptAsset = Assets.ScriptAsset;

const Entity = @import("../GameObjects/Entity.zig");

const Tracy = @import("../Core/Tracy.zig");

pub fn RunEntityScript(scene_manager: *SceneManager, comptime script_type: type, args: anytype, frame_allocator: std.mem.Allocator) !bool {
    const zone = Tracy.ZoneInit("RunEntityScript", @src());
    defer zone.Deinit();

    const ecs_manager_go = scene_manager.mECSManagerGO;

    const scene_stack_scenes = try scene_manager.mECSManagerSC.GetGroup(GroupQuery{ .Component = StackPosComponent }, frame_allocator);
    std.sort.insertion(SceneType, scene_stack_scenes.items, scene_manager.mECSManagerSC, SceneManager.SortScenesFunc);

    var cont_bool = true;
    for (scene_stack_scenes.items) |scene_id| {
        if (cont_bool == false) break;

        var scene_scripts = try ecs_manager_go.GetGroup(GroupQuery{ .Component = script_type }, frame_allocator);
        scene_manager.FilterEntityScriptsByScene(&scene_scripts, scene_id, frame_allocator);

        for (scene_scripts.items) |script_id| {
            const script_component = ecs_manager_go.GetComponent(EntityScriptComponent, script_id).?;

            const asset_handle = script_component.mScriptAssetHandle;
            const script_asset = try asset_handle.GetAsset(ScriptAsset);

            const run_func = script_asset.mLib.lookup(script_type.RunFuncSig, "Run").?;

            var entity = Entity{ .mEntityID = script_component.mParent, .mECSManagerRef = &scene_manager.mECSManagerGO };

            const combined_args = .{ StaticEngineContext.GetInstance(), &frame_allocator, &entity } ++ args;

            cont_bool = cont_bool and @call(.auto, run_func, combined_args);
        }
    }
    return cont_bool;
}

pub fn RunSceneScript(scene_manager: *SceneManager, comptime script_type: type, args: anytype, frame_allocator: std.mem.Allocator) !bool {
    comptime {
        if (script_type != OnSceneStartScript) {
            @compileError("Cannot use this type as a Scene Script type!");
        }
    }

    const ecs_manager_sc = scene_manager.mECSManagerSC;

    const scene_stack_scenes = try scene_manager.mECSManagerSC.GetGroup(GroupQuery{ .Component = StackPosComponent }, frame_allocator);
    std.sort.insertion(SceneType, scene_stack_scenes.items, scene_manager.mECSManagerSC, SceneManager.SortScenesFunc);

    var cont_bool = true;
    for (scene_stack_scenes.items) |scene_id| {
        if (cont_bool == false) break;

        var scene_scripts = try ecs_manager_sc.GetGroup(GroupQuery{ .Component = script_type }, frame_allocator);
        scene_manager.FilterSceneScriptsByScene(&scene_scripts, scene_id, frame_allocator);

        for (scene_scripts.items) |script_id| {
            const script_component = ecs_manager_sc.GetComponent(SceneScriptComponent, script_id).?;
            if (script_component.mScriptAssetHandle) |asset_handle| {
                const script_asset = try asset_handle.GetAsset(ScriptAsset);
                const run_func = script_asset.mLib.lookup(script_type.RunFuncSig, "Run").?;

                var scene = SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &scene_manager.mECSManagerGO, .mECSManagerSCRef = &scene_manager.mECSManagerSC };

                const combined_args = .{ StaticEngineContext.GetInstance(), &frame_allocator, &scene } ++ args;

                cont_bool = cont_bool and @call(.auto, run_func, combined_args);
            }
        }
    }
    return cont_bool;
}
pub fn RunEntityScriptEditor(scene_manager: *SceneManager, comptime script_type: type, args: anytype, editor_scene_layer: *SceneLayer, frame_allocator: std.mem.Allocator) !bool {
    comptime {
        if (script_type != OnInputPressedScript and
            script_type != OnUpdateInputScript)
        {
            @compileError("Cannot use this type as a Entity Script type!");
        }
    }

    const ecs_manager_go = scene_manager.mECSManagerGO;

    var scene_scripts = try ecs_manager_go.GetGroup(GroupQuery{ .Component = script_type }, frame_allocator);
    scene_manager.FilterEntityScriptsByScene(&scene_scripts, editor_scene_layer.mSceneID);

    for (scene_scripts.items) |script_id| {
        const script_component = ecs_manager_go.GetComponent(EntityScriptComponent, script_id);
        if (script_component.mScriptAssetHandle) |asset_handle| {
            const script_asset = try asset_handle.GetAsset(ScriptAsset);
            const run_func = script_asset.mLib.lookup(script_type.RunFuncSig, "Run").?;

            var entity = Entity{ .mEntityID = script_component.mParent, .mECSManagerRef = &scene_manager.mECSManagerGO };

            const combined_args = .{ StaticEngineContext.GetInstance(), &frame_allocator, &entity } ++ args;

            _ = @call(.auto, run_func, combined_args);
        }
    }
    return true;
}

pub fn RunSceneScriptEditor(scene_manager: *SceneManager, comptime script_type: type, args: anytype, editor_scene_layer: *SceneLayer, frame_allocator: std.mem.Allocator) !bool {
    comptime {
        if (script_type != OnSceneStartScript) {
            @compileError("Cannot use this type as a Scene Script type!");
        }
    }

    const ecs_manager_sc = scene_manager.mECSManagerSC;

    var scene_scripts = try ecs_manager_sc.GetGroup(GroupQuery{ .Component = script_type }, frame_allocator);
    scene_manager.FilterSceneScriptsByScene(&scene_scripts, editor_scene_layer.mSceneID);

    for (scene_scripts.items) |script_id| {
        const script_component = ecs_manager_sc.GetComponent(SceneScriptComponent, script_id);
        if (script_component.mScriptAssetHandle) |asset_handle| {
            const script_asset = try asset_handle.GetAsset(ScriptAsset);
            const run_func = script_asset.mLib.lookup(script_type.RunFuncSig, "Run").?;

            var scene = SceneLayer{ .mSceneID = editor_scene_layer.mSceneID, .mECSManagerGORef = &scene_manager.mECSManagerGO, .mECSManagerSCRef = &scene_manager.mECSManagerSC };

            const combined_args = .{ StaticEngineContext.GetInstance(), &frame_allocator, &scene } ++ args;

            _ = @call(.auto, run_func, combined_args);
        }
    }
    return true;
}

fn _ValidateEntityType(script_type: type) void {
    comptime var is_valid: bool = false;
    for (EntityScriptList) |s_type| {
        if (script_type == s_type) {
            is_valid = true;
        }
    }
    if (is_valid == false) {
        const type_name = std.fmt.comptimePrint(" {s}\n", .{@typeName(script_type)});
        @compileError("Invalid type passed!" ++ type_name);
    }
}

fn _ValidateSceneType(script_type: type) void {
    comptime var is_valid: bool = false;
    for (SceneScriptList) |s_type| {
        if (script_type == s_type) {
            is_valid = true;
        }
    }
    if (is_valid == false) {
        const type_name = std.fmt.comptimePrint(" {s}\n", .{@typeName(script_type)});
        @compileError("Invalid type passed!" ++ type_name);
    }
}
