//! This file exists as a location to group together all the functions that run
//! scripts rather than cluddering up other engine files like scene manager or something
const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
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
const EntityInputPressedScript = EntityComponents.OnInputPressedScript;
const EntityOnUpdateScript = EntityComponents.OnUpdateScript;
const EntitySceneComponent = EntityComponents.SceneIDComponent;
const CameraComponent = EntityComponents.CameraComponent;

const SceneScriptList = @import("../Scene/SceneComponents.zig").ScriptList;
const SceneComponents = @import("../Scene/SceneComponents.zig");
const SceneScriptComponent = SceneComponents.ScriptComponent;
const StackPosComponent = SceneComponents.StackPosComponent;
const SceneSceneStartScript = SceneComponents.OnSceneStartScript;

const AssetsList = @import("../Assets/Assets.zig").AssetsList;
const Assets = @import("../Assets/Assets.zig");
const ScriptAsset = Assets.ScriptAsset;
const ScriptType = ScriptAsset.ScriptType;
const AssetHandle = @import("../Assets/AssetHandle.zig");

const Entity = @import("../GameObjects/Entity.zig");

const Tracy = @import("../Core/Tracy.zig");

pub fn RunEntityScript(engine_context: *EngineContext, comptime script_type: type, scene_manager: *SceneManager, args: anytype) !bool {
    _ValidateEntityType(script_type);
    const zone = Tracy.ZoneInit("RunEntityScript", @src());
    defer zone.Deinit();

    const ecs_manager_sc = scene_manager.mECSManagerSC;
    const ecs_manager_go = scene_manager.mECSManagerGO;
    const frame_allocator = engine_context.mFrameAllocator;

    const scene_stack_scenes = try ecs_manager_sc.GetGroup(frame_allocator, GroupQuery{ .Component = StackPosComponent });
    std.sort.insertion(SceneType, scene_stack_scenes.items, ecs_manager_sc, SceneManager.SortScenesFunc);

    var cont_bool = true;
    for (scene_stack_scenes.items) |scene_id| {
        if (cont_bool == false) break;

        var scene_scripts = try ecs_manager_go.GetGroup(frame_allocator, GroupQuery{ .Component = script_type });
        scene_manager.FilterEntityScriptsByScene(frame_allocator, &scene_scripts, scene_id);

        for (scene_scripts.items) |script_id| {
            if (ecs_manager_go.GetComponent(EntityScriptComponent, script_id)) |script_component| {
                if (script_component.mScriptAssetHandle.mID == AssetHandle.NullHandle) continue;
                const asset_handle = script_component.mScriptAssetHandle;
                const script_asset = try asset_handle.GetAsset(engine_context, ScriptAsset);

                var entity = Entity{ .mEntityID = script_component.mParent, .mECSManagerRef = &scene_manager.mECSManagerGO };

                const combined_args = .{ engine_context, &entity } ++ args;
                cont_bool = cont_bool and script_asset.Run(script_type, combined_args);
            }
        }
    }
    return cont_bool;
}

pub fn RunSceneScript(engine_context: *EngineContext, comptime script_type: type, scene_manager: *SceneManager, args: anytype) !bool {
    _ValidateSceneType(script_type);

    const ecs_manager_sc = scene_manager.mECSManagerSC;
    const frame_allocator = engine_context.mFrameAllocator;

    const scene_stack_scenes = try scene_manager.mECSManagerSC.GetGroup(frame_allocator, GroupQuery{ .Component = StackPosComponent });
    std.sort.insertion(SceneType, scene_stack_scenes.items, scene_manager.mECSManagerSC, SceneManager.SortScenesFunc);

    var cont_bool = true;
    for (scene_stack_scenes.items) |scene_id| {
        if (cont_bool == false) break;

        var scene_scripts = try ecs_manager_sc.GetGroup(frame_allocator, GroupQuery{ .Component = script_type });
        scene_manager.FilterSceneScriptsByScene(&scene_scripts, scene_id, frame_allocator);

        for (scene_scripts.items) |script_id| {
            if (ecs_manager_sc.GetComponent(SceneScriptComponent, script_id)) |script_component| {
                if (script_component.mScriptAssetHandle.mID == AssetHandle.NullHandle) continue;
                const asset_handle = script_component.mScriptAssetHandle;
                const script_asset = try asset_handle.GetAsset(ScriptAsset);

                var scene = SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &scene_manager.mECSManagerGO, .mECSManagerSCRef = &scene_manager.mECSManagerSC };

                const combined_args = .{ engine_context, &scene } ++ args;

                cont_bool = cont_bool and script_asset.Run(combined_args);
            }
        }
    }
    return cont_bool;
}

pub fn RunEntityScriptEditor(engine_context: *EngineContext, comptime script_type: type, scene_manager: *SceneManager, editor_scene_layer: *SceneLayer, args: anytype) !bool {
    _ValidateEntityType(script_type);

    const ecs_manager_go = scene_manager.mECSManagerGO;
    const frame_allocator = engine_context.mFrameAllocator;

    var scene_scripts = try ecs_manager_go.GetGroup(frame_allocator, GroupQuery{ .Component = script_type });
    scene_manager.FilterEntityScriptsByScene(engine_context.mFrameAllocator, &scene_scripts, editor_scene_layer.mSceneID);

    for (scene_scripts.items) |script_id| {
        if (ecs_manager_go.GetComponent(EntityScriptComponent, script_id)) |script_component| {
            if (script_component.mScriptAssetHandle.mID == AssetHandle.NullHandle) continue;
            const asset_handle = script_component.mScriptAssetHandle;
            const script_asset = try asset_handle.GetAsset(engine_context, ScriptAsset);

            var entity = Entity{ .mEntityID = script_component.mParent, .mECSManagerRef = &scene_manager.mECSManagerGO };

            const combined_args = .{ engine_context, &entity } ++ args;

            _ = script_asset.Run(script_type, combined_args);
        }
    }
    return true;
}

pub fn RunSceneScriptEditor(engine_context: *EngineContext, comptime script_type: type, scene_manager: *SceneManager, editor_scene_layer: *SceneLayer, args: anytype) !bool {
    _ValidateSceneType(script_type);

    const ecs_manager_sc = scene_manager.mECSManagerSC;
    const frame_allocator = engine_context.mFrameAllocator;

    var scene_scripts = try ecs_manager_sc.GetGroup(frame_allocator, GroupQuery{ .Component = script_type });
    scene_manager.FilterSceneScriptsByScene(&scene_scripts, editor_scene_layer.mSceneID);

    for (scene_scripts.items) |script_id| {
        if (ecs_manager_sc.GetComponent(SceneScriptComponent, script_id)) |script_component| {
            if (script_component.mScriptAssetHandle.mID == AssetHandle.NullHandle) continue;
            const asset_handle = script_component.mScriptAssetHandle;
            const script_asset = try asset_handle.GetAsset(ScriptAsset);

            var scene = SceneLayer{ .mSceneID = editor_scene_layer.mSceneID, .mECSManagerGORef = &scene_manager.mECSManagerGO, .mECSManagerSCRef = &scene_manager.mECSManagerSC };

            const combined_args = .{ engine_context, &scene } ++ args;

            script_asset.Run(combined_args);
        }
    }
    return true;
}

fn _GetFnInfo(comptime func_type_info: std.builtin.Type, comptime func_name: []const u8, comptime type_name: []const u8) std.builtin.Type.Fn {
    return switch (func_type_info) {
        .Fn => |info| info,
        else => @compileError(func_name ++ " must be a function" ++ type_name),
    };
}

pub fn _ValidateScript(comptime script_type: type) void {
    const type_name = std.fmt.comptimePrint(" {s}\n", .{@typeName(script_type)});

    if (@hasDecl(script_type, "Run") == false) {
        @compileError("Script requires a run function" ++ type_name);
    } else {
        // Check to ensure return type is bool
        comptime {
            const RunFn = @TypeOf(@field(script_type, "Run"));
            const run_func_info = @typeInfo(RunFn);
            const fn_info = _GetFnInfo(run_func_info, "Run", type_name);

            if (fn_info.return_type) |return_type| {
                if (return_type != bool) {
                    @compileError("Run function must return bool" ++ type_name);
                }
            } else {
                @compileError("Run function must return bool" ++ type_name);
            }
        }
    }

    if (@hasDecl(script_type, "GetScriptType") == false) {
        @compileError("Script requires a GetScriptType function" ++ type_name);
    } else {
        // Check to ensure it takes no parameters and it returns a ScriptType
        comptime {
            const GetScriptTypeFn = @TypeOf(@field(script_type, "GetScriptType"));
            const get_script_type_func_info = @typeInfo(GetScriptTypeFn);
            const fn_info = _GetFnInfo(get_script_type_func_info, "GetScriptType", type_name);

            if (fn_info.params.len != 0) {
                @compileError("GetScriptType function must take no parameters" ++ type_name);
            }
            if (fn_info.return_type) |return_type| {
                if (return_type != ScriptType) {
                    @compileError("GetScriptType function must return ScriptType" ++ type_name);
                }
            } else {
                @compileError("GetScriptType function must return ScriptType" ++ type_name);
            }
        }
    }
}

fn _ValidateEntityType(script_type: type) void {
    comptime var is_valid: bool = false;
    inline for (EntityScriptList) |s_type| {
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
    inline for (SceneScriptList) |s_type| {
        if (script_type == s_type) {
            is_valid = true;
        }
    }
    if (is_valid == false) {
        const type_name = std.fmt.comptimePrint(" {s}\n", .{@typeName(script_type)});
        @compileError("Invalid type passed!" ++ type_name);
    }
}
