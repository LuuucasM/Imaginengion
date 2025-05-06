//! This file exists as a location to group together all the functions that run
//! scripts rather than cluddering up other engine files like scene manager or something
const std = @import("std");
const StaticEngineContext = @import("../Core/EngineContext.zig");
const EngineContext = StaticEngineContext.EngineContext;
const SceneManager = @import("../Scene/SceneManager.zig");
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

pub fn OnInputPressedEvent(scene_manager: *SceneManager, e: InputPressedEvent) !bool {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const ecs_manager = scene_manager.mECSManager;

    const input_pressed_entities = try scene_manager.mECSManager.GetGroup(.{ .Component = OnInputPressedScript }, allocator);

    var iter = std.mem.reverseIterator(scene_manager.mSceneStack.items);
    var cont_bool = true;
    while (iter.next()) |*scene_layer| {
        if (cont_bool == false) break;

        var scene_scripts = try std.ArrayList(u32).initCapacity(allocator, scene_layer.mEntityList.items.len);
        try scene_scripts.appendSlice(scene_layer.mEntityList.items);
        try ecs_manager.EntityListIntersection(&scene_scripts, input_pressed_entities, allocator);

        for (scene_scripts.items) |script_id| {
            const script_component = ecs_manager.GetComponent(ScriptComponent, script_id);
            const script_asset = try script_component.mScriptAssetHandle.GetAsset(ScriptAsset);
            const run_func = script_asset.mLib.lookup(*const fn (*EngineContext, *const std.mem.Allocator, *Entity, *const InputPressedEvent) callconv(.C) bool, "Run").?;

            var entity = Entity{ .mEntityID = script_component.mParent, .mSceneLayerRef = @constCast(scene_layer) };

            cont_bool = cont_bool and run_func(StaticEngineContext.GetInstance(), &allocator, &entity, &e);
        }
    }
    return cont_bool;
}

pub fn OnUpdateInput(scene_manager: *SceneManager) !bool {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const ecs_manager = scene_manager.mECSManager;

    const update_input_entities = try scene_manager.mECSManager.GetGroup(.{ .Component = OnUpdateInputScript }, allocator);

    var iter = std.mem.reverseIterator(scene_manager.mSceneStack.items);
    var cont_bool = true;
    while (iter.next()) |*scene_layer| {
        if (cont_bool == false) break;

        var scene_scripts = try std.ArrayList(u32).initCapacity(allocator, scene_layer.mEntityList.items.len);
        try scene_scripts.appendSlice(scene_layer.mEntityList.items);
        try ecs_manager.EntityListIntersection(&scene_scripts, update_input_entities, allocator);

        for (scene_scripts.items) |script_id| {
            const script_component = ecs_manager.GetComponent(ScriptComponent, script_id);
            const script_asset = try script_component.mScriptAssetHandle.GetAsset(ScriptAsset);
            const run_func = script_asset.mLib.lookup(*const fn (*EngineContext, *const std.mem.Allocator, *Entity) callconv(.C) bool, "Run").?;

            var entity = Entity{ .mEntityID = script_component.mParent, .mSceneLayerRef = @constCast(scene_layer) };

            cont_bool = cont_bool and run_func(StaticEngineContext.GetInstance(), &allocator, &entity);
        }
    }
    return cont_bool;
}

pub fn OnInputPressedEventEditor(editor_scene_layer: *SceneLayer, e: InputPressedEvent, editor_window_in_focus: bool) !bool {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var ecs_manager = editor_scene_layer.mECSManagerRef;

    const input_pressed_entities = if (editor_window_in_focus == true) try ecs_manager.GetGroup(.{ .Component = OnInputPressedScript }, allocator) else try ecs_manager.GetGroup(.{ .Not = .{ .mFirst = GroupQuery{ .Component = OnInputPressedScript }, .mSecond = GroupQuery{ .Component = CameraComponent } } }, allocator);

    var scene_scripts = try std.ArrayList(u32).initCapacity(allocator, editor_scene_layer.mEntityList.items.len);
    try scene_scripts.appendSlice(editor_scene_layer.mEntityList.items);
    try ecs_manager.EntityListIntersection(&scene_scripts, input_pressed_entities, allocator);

    for (scene_scripts.items) |script_id| {
        const script_component = ecs_manager.GetComponent(ScriptComponent, script_id);
        const script_asset = try script_component.mScriptAssetHandle.GetAsset(ScriptAsset);
        const run_func = script_asset.mLib.lookup(*const fn (*EngineContext, *const std.mem.Allocator, *Entity, *const InputPressedEvent) callconv(.C) bool, "Run").?;

        var entity = Entity{ .mEntityID = script_component.mParent, .mSceneLayerRef = @constCast(editor_scene_layer) };

        run_func(StaticEngineContext.GetInstance(), &allocator, &entity, &e);
    }

    return true;
}

pub fn OnUpdateInputEditor(editor_scene_layer: *SceneLayer, editor_window_in_focus: bool) !bool {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const ecs_manager = editor_scene_layer.mECSManagerRef;

    const update_input_entities = if (editor_window_in_focus == true) try ecs_manager.GetGroup(.{ .Component = OnUpdateInputScript }, allocator) else try ecs_manager.GetGroup(.{ .Not = .{ .mFirst = GroupQuery{ .Component = OnUpdateInputScript }, .mSecond = GroupQuery{ .Component = CameraComponent } } }, allocator);

    var scene_scripts = try std.ArrayList(u32).initCapacity(allocator, editor_scene_layer.mEntityList.items.len);
    try scene_scripts.appendSlice(editor_scene_layer.mEntityList.items);
    try ecs_manager.EntityListIntersection(&scene_scripts, update_input_entities, allocator);

    for (scene_scripts.items) |script_id| {
        const script_component = ecs_manager.GetComponent(ScriptComponent, script_id);
        const script_asset = try script_component.mScriptAssetHandle.GetAsset(ScriptAsset);
        const run_func = script_asset.mLib.lookup(*const fn (*EngineContext, *const std.mem.Allocator, *Entity) callconv(.C) bool, "Run").?;

        var entity = Entity{ .mEntityID = script_component.mParent, .mSceneLayerRef = @constCast(editor_scene_layer) };

        run_func(StaticEngineContext.GetInstance(), &allocator, &entity);
    }

    return true;
}
