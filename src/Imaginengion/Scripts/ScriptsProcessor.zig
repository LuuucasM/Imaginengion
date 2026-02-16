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

pub fn RunEntityScript(comptime script_type: type, comptime world_type: EngineContext.WorldType, engine_context: *EngineContext, args: anytype) !bool {
    _ValidateEntityType(script_type);
    const zone = Tracy.ZoneInit("RunEntityScript", @src());
    defer zone.Deinit();

    const scene_manager = switch (world_type) {
        .Game => engine_context.mGameWorld,
        .Editor => engine_context.mEditorWorld,
        .Simulate => engine_context.mSimulateWorld,
    };

    const frame_allocator = engine_context.FrameAllocator();

    const scene_stack_scenes = try scene_manager.mECSManagerSC.GetGroup(frame_allocator, GroupQuery{ .Component = StackPosComponent });
    std.sort.insertion(SceneType, scene_stack_scenes.items, scene_manager.mECSManagerSC, SceneManager.SortScenesFunc);

    var cont_bool = true;
    for (scene_stack_scenes.items) |scene_id| {
        if (cont_bool == false) break;
        const scene_layer = scene_manager.GetSceneLayer(scene_id);

        const scene_entity_scripts = try scene_layer.GetEntityGroup(frame_allocator, .{ .Component = script_type });
        for (scene_entity_scripts.items) |script_id| {
            const script_entity = scene_layer.GetEntity(script_id);

            if (script_entity.GetComponent(EntityScriptComponent)) |script_component| {
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

pub fn RunSceneScript(comptime script_type: type, comptime world_type: EngineContext.WorldType, engine_context: *EngineContext, args: anytype) !bool {
    _ValidateSceneType(script_type);
    const zone = Tracy.ZoneInit("RunSceneScript", @src());
    defer zone.Deinit();

    const scene_manager = switch (world_type) {
        .Game => engine_context.mGameWorld,
        .Editor => engine_context.mEditorWorld,
        .Simulate => engine_context.mSimulateWorld,
    };

    const frame_allocator = engine_context.FrameAllocator();

    const scene_stack_scenes = try scene_manager.GetSceneGroup(frame_allocator, GroupQuery{ .Component = StackPosComponent });
    std.sort.insertion(SceneType, scene_stack_scenes.items, scene_manager.mECSManagerSC, SceneManager.SortScenesFunc);

    var cont_bool = true;
    for (scene_stack_scenes.items) |scene_id| {
        if (cont_bool == false) break;

        const scene_layer = scene_manager.GetSceneLayer(scene_id);

        const scene_scripts = scene_layer.GetSceneGroup(frame_allocator, GroupQuery{ .Component = script_type });

        for (scene_scripts.items) |script_id| {
            const script_scene = scene_manager.GetSceneLayer(script_id);
            if (script_scene.GetComponent(SceneScriptComponent)) |script_component| {
                if (script_component.mScriptAssetHandle.mID == AssetHandle.NullHandle) continue;
                const asset_handle = script_component.mScriptAssetHandle;
                const script_asset = try asset_handle.GetAsset(engine_context, ScriptAsset);

                var scene = SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &scene_manager.mECSManagerGO, .mECSManagerSCRef = &scene_manager.mECSManagerSC };

                const combined_args = .{ engine_context, &scene } ++ args;

                cont_bool = cont_bool and script_asset.Run(script_type, combined_args);
            }
        }
    }
    return cont_bool;
}

fn _GetFnInfo(comptime func_type_info: std.builtin.Type, comptime func_name: []const u8, comptime type_name: []const u8) std.builtin.Type.Fn {
    return switch (func_type_info) {
        .Fn => |info| info,
        else => @compileError(func_name ++ " must be a function" ++ type_name),
    };
}

pub fn _ValidateScript(comptime script_type: type) void {
    const type_name = std.fmt.comptimePrint(" {s}\n", .{@typeName(script_type)});
    std.debug.assert(@hasDecl(script_type, "Run"));
    std.debug.assert(@hasDecl(script_type, "GetScriptType"));

    //validate run function
    const RunFn = @TypeOf(@field(script_type, "Run"));
    const run_func_info = @typeInfo(RunFn);
    const run_fn_info = _GetFnInfo(run_func_info, "Run", type_name);

    if (run_fn_info.return_type) |return_type| {
        if (return_type != bool) {
            @compileError("Run function must return bool" ++ type_name);
        }
    } else {
        @compileError("Run function must return bool" ++ type_name);
    }

    //validate GetScriptType
    const GetScriptTypeFn = @TypeOf(@field(script_type, "GetScriptType"));
    const get_script_type_func_info = @typeInfo(GetScriptTypeFn);
    const type_fn_info = _GetFnInfo(get_script_type_func_info, "GetScriptType", type_name);

    if (type_fn_info.params.len != 0) {
        @compileError("GetScriptType function must take no parameters" ++ type_name);
    }
    if (type_fn_info.return_type) |return_type| {
        if (return_type != ScriptType) {
            @compileError("GetScriptType function must return ScriptType" ++ type_name);
        }
    } else {
        @compileError("GetScriptType function must return ScriptType" ++ type_name);
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
