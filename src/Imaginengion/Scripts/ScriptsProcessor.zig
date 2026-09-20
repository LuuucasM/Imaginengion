//! This file exists as a location to group together all the functions that run
//! scripts rather than cluddering up other engine files like scene manager or something
//!
//! A script is a child object of the thing it belongs to: it carries a ScriptComponent
//! holding the asset handle and a tag component saying when it runs. That shape is the
//! same for entities, scenes, players and game contexts, so RunScript covers all four.
const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const WorldManager = @import("../Core/WorldManager.zig");
const GroupQuery = @import("../ECS/ECSManager.zig").GroupQuery;

const Entity = @import("../ECSObjects/Entity.zig");
const GameContext = @import("../ECSObjects/GameContext.zig");
const Player = @import("../ECSObjects/Player.zig");
const Scene = @import("../ECSObjects/Scene.zig");

const EComponents = @import("../ECSComponents/EComponents.zig");
const GCComponents = @import("../ECSComponents/GCComponents.zig");
const PComponents = @import("../ECSComponents/PComponents.zig");
const SComponents = @import("../ECSComponents/SComponents.zig");

const ScriptComponent = @import("../ECSComponents/Shared/ScriptComponent.zig");
const EntitySceneComponent = EComponents.EntitySceneComponent;
const StackPosComponent = SComponents.StackPosComponent;

const Assets = @import("../ECSComponents/AComponents.zig");
const ScriptAsset = Assets.ScriptAsset;
const ScriptType = ScriptAsset.ScriptType;
const AssetHandle = @import("../ECSObjects/AssetHandle.zig");

const Tracy = @import("../Core/Tracy.zig");

/// Runs every script of the given tag type belonging to objects of ObjectType, in scene
/// stack order, and stops early if a script asks to consume the event.
pub fn RunScript(
    comptime ObjectType: type,
    comptime script_type: type,
    comptime world_type: EngineContext.WorldType,
    engine_context: *EngineContext,
    args: anytype,
) !bool {
    _ValidateScriptType(ObjectType, script_type);

    const zone = Tracy.ZoneInit("RunScript", @src());
    defer zone.Deinit();

    const world_manager = switch (world_type) {
        .Game => &engine_context.mGameWorld,
        .Editor => &engine_context.mEditorWorld,
        .Simulate => &engine_context.mSimulateWorld,
    };

    const frame_allocator = engine_context.FrameAllocator();
    const manager = world_manager.GetManager(ObjectType);

    const script_ids = try manager.GetGroup(frame_allocator, GroupQuery{ .Component = script_type });
    SortByOwnerStackPos(ObjectType, world_manager, script_ids.items);

    var cont_bool = true;
    for (script_ids.items) |script_id| {
        if (cont_bool == false) break;

        const script_component = manager.GetComponent(ScriptComponent, script_id) orelse continue;
        if (script_component.mScriptAssetHandle.mID == AssetHandle.NullObject) continue;

        const script_asset = try script_component.mScriptAssetHandle.GetAsset(engine_context, ScriptAsset);

        var owner = ObjectType{ .mID = @intCast(script_component.mParent), .mManager = world_manager };

        const combined_args = .{ engine_context, &owner } ++ args;
        cont_bool = cont_bool and script_asset.Run(script_type, combined_args);
    }

    return cont_bool;
}

/// Scripts run top layer first, matching the order scenes are drawn in. The sort is
/// stable, so scripts sharing a layer keep the order the ECS handed them back, and for
/// object types with no place in the scene stack it leaves the list alone.
fn SortByOwnerStackPos(comptime ObjectType: type, world_manager: *WorldManager, script_ids: []ObjectType.Type) void {
    if (ObjectType != Entity and ObjectType != Scene) return;

    const Sorter = struct {
        fn StackPosOf(wm: *WorldManager, script_id: ObjectType.Type) usize {
            const script_component = wm.GetManager(ObjectType).GetComponent(ScriptComponent, script_id) orelse return 0;
            return OwnerStackPos(ObjectType, wm, @intCast(script_component.mParent));
        }
        fn lessThan(wm: *WorldManager, a: ObjectType.Type, b: ObjectType.Type) bool {
            return StackPosOf(wm, b) < StackPosOf(wm, a);
        }
    };

    std.sort.insertion(ObjectType.Type, script_ids, world_manager, Sorter.lessThan);
}

/// Where the script's owner sits in the scene stack. A scene answers for itself, an
/// entity answers with the scene it lives in, and anything that never went through
/// CreateScene reports 0 so it sorts last rather than crashing.
fn OwnerStackPos(comptime ObjectType: type, world_manager: *WorldManager, owner_id: ObjectType.Type) usize {
    if (ObjectType == Scene) {
        const stack_pos = world_manager.mSManager.GetComponent(StackPosComponent, owner_id) orelse return 0;
        return stack_pos.mPosition;
    } else if (ObjectType == Entity) {
        const scene_component = world_manager.mEManager.GetComponent(EntitySceneComponent, owner_id) orelse return 0;
        const stack_pos = world_manager.mSManager.GetComponent(StackPosComponent, scene_component.mScene.mID) orelse return 0;
        return stack_pos.mPosition;
    } else {
        return 0;
    }
}

/// The script tags an object of this type is allowed to carry.
fn ScriptsListFor(comptime ObjectType: type) []const type {
    if (ObjectType == Entity) {
        return &EComponents.ScriptsList;
    } else if (ObjectType == GameContext) {
        return &GCComponents.ScriptsList;
    } else if (ObjectType == Player) {
        return &PComponents.ScriptsList;
    } else if (ObjectType == Scene) {
        return &SComponents.ScriptsList;
    } else {
        @compileError(std.fmt.comptimePrint("{s} is not a scriptable object type", .{@typeName(ObjectType)}));
    }
}

fn _ValidateScriptType(comptime ObjectType: type, comptime script_type: type) void {
    comptime var is_valid: bool = false;
    const scripts_list = comptime ScriptsListFor(ObjectType);
    inline for (scripts_list) |s_type| {
        if (script_type == s_type) {
            is_valid = true;
        }
    }
    if (is_valid == false) {
        @compileError(std.fmt.comptimePrint("{s} is not a script type for {s}\n", .{ @typeName(script_type), @typeName(ObjectType) }));
    }
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
