//! This file exists as a location to group together all the functions that run
//! scripts rather than cluddering up other engine files like scene manager or something
const std = @import("std");
const StaticEngineContext = @import("../Core/EngineContext.zig");
const EngineContext = StaticEngineContext.EngineContext;
const SceneManager = @import("../Scene/SceneManager.zig");

const GameEvent = @import("../Events/GameEvent.zig");
const SystemEvent = @import("../Events/SystemEvent.zig");
const InputPressedEvent = SystemEvent.InputPressedEvent;

const Components = @import("../GameObjects/Components.zig");
const ScriptComponent = Components.ScriptComponent;
const OnInputPressedScript = Components.OnInputPressedScript;
const OnUpdateInputScript = Components.OnUpdateInputScript;
const SceneIDComponent = Components.SceneIDComponent;

const Assets = @import("../Assets/Assets.zig");
const ScriptAsset = Assets.ScriptAsset;

const Entity = @import("../GameObjects/Entity.zig");

pub fn OnInputPressedEvent(scene_manager: *SceneManager, e: InputPressedEvent) !bool {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const group = try scene_manager.mECSManager.GetGroup(.{ .Component = OnInputPressedScript }, allocator);

    var iter = std.mem.reverseIterator(scene_manager.mSceneStack.items);
    var cont_bool = true;
    while (iter.next()) |*scene_layer| {
        if (cont_bool == false) break;
        //sort group by scene layer where the first items in the group are entity id's which
        //are from the top most layer, than second most layer, etc
        for (group.items) |script_id| {
            const script_component = scene_manager.mECSManager.GetComponent(ScriptComponent, script_id);
            //const scene_uuid_component = scene_manager.mECSManager.GetComponent(SceneIDComponent, script_component.mParent);

            //if (scene_uuid_component.SceneID != scene_layer.mUUID) continue;

            const script_asset = try script_component.mScriptAssetHandle.GetAsset(ScriptAsset);
            const run_func = script_asset.mLib.lookup(*const fn (*EngineContext, *const std.mem.Allocator, *Entity, *const InputPressedEvent) callconv(.C) bool, "Run").?;

            var entity = Entity{ .mEntityID = script_component.mParent, .mECSManagerRef = scene_layer.mECSManagerRef };

            cont_bool = cont_bool and run_func(StaticEngineContext.GetInstance(), &allocator, &entity, &e);
        }
    }
    return cont_bool;
}

pub fn OnUpdateInput(scene_manager: *SceneManager) !bool {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const group = try scene_manager.mECSManager.GetGroup(.{ .Component = OnUpdateInputScript }, allocator);

    var iter = std.mem.reverseIterator(scene_manager.mSceneStack.items);
    var cont_bool = true;
    while (iter.next()) |*scene_layer| {
        if (cont_bool == false) break;
        //sort group by scene layer where the first items in the group are entity id's which
        //are from the top most layer, than second most layer, etc
        for (group.items) |script_id| {
            const script_component = scene_manager.mECSManager.GetComponent(ScriptComponent, script_id);
            //const scene_uuid_component = scene_manager.mECSManager.GetComponent(SceneIDComponent, script_component.mParent);

            //if (scene_uuid_component.SceneID != scene_layer.mUUID) continue;

            const script_asset = try script_component.mScriptAssetHandle.GetAsset(ScriptAsset);
            const run_func = script_asset.mLib.lookup(*const fn (*EngineContext, *const std.mem.Allocator, *Entity) callconv(.C) bool, "Run").?;

            var entity = Entity{ .mEntityID = script_component.mParent, .mECSManagerRef = scene_layer.mECSManagerRef };

            cont_bool = cont_bool and run_func(StaticEngineContext.GetInstance(), &allocator, &entity);
        }
    }
    return cont_bool;
}
