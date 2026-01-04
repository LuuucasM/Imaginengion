const std = @import("std");
const ECSManagerScenes = @import("SceneManager.zig").ECSManagerScenes;
const ECSManagerGameObj = @import("SceneManager.zig").ECSManagerGameObj;
const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;
const SceneComponents = @import("SceneComponents.zig");
const EntityComponents = @import("../GameObjects/Components.zig");
const SceneIDComponent = SceneComponents.IDComponent;
const SceneScriptComponent = SceneComponents.ScriptComponent;
const EntityIDComponent = EntityComponents.IDComponent;
const EntityNameComponent = EntityComponents.NameComponent;
const EntitySceneComponent = EntityComponents.SceneIDComponent;
const TransformComponent = EntityComponents.TransformComponent;
const EntityScriptComponent = EntityComponents.ScriptComponent;
const Entity = @import("../GameObjects/Entity.zig");
const GenUUID = @import("../Core/UUID.zig").GenUUID;
const EngineContext = @import("../Core/EngineContext.zig");

pub const Type = u32;
pub const NullScene: Type = std.math.maxInt(Type);
const SceneLayer = @This();

mSceneID: Type = NullScene,
mECSManagerGORef: *ECSManagerGameObj = undefined,
mECSManagerSCRef: *ECSManagerScenes = undefined,

//for the scenes themselves
pub fn AddComponent(self: SceneLayer, comptime component_type: type, component: ?component_type) !*component_type {
    return try self.mECSManagerSCRef.AddComponent(component_type, self.mSceneID, component);
}
pub fn RemoveComponent(self: SceneLayer, args: anytype) !void {
    const t = @TypeOf(args);
    const t_info = @typeInfo(t);

    switch (t_info) {
        .type => {
            if (args.Category == .Unique) {
                return try self.mECSManagerSCRef.RemoveComponent(args, self.mEntityID);
            }
        },
        .@"struct" => |s| {
            if (s.is_tuple == true and s.fields.len == 2 and s.fields[0].type == type and s.fields[1].type == Entity.Type and s.fields[0].type.Category == .Multiple) {
                return try self.mECSManagerSCRef.RemoveComponent(args[0], args[1]);
            }
        },
        else => {},
    }

    @compileError("Entity.RemoveComponent can not be called with these arguments");
}
pub fn GetComponent(self: SceneLayer, comptime component_type: type) ?*component_type {
    return self.mECSManagerSCRef.GetComponent(component_type, self.mSceneID);
}
pub fn HasComponent(self: SceneLayer, comptime component_type: type) bool {
    return self.mECSManagerSCRef.HasComponent(component_type, self.mSceneID);
}
pub fn GetEntityGroup(self: SceneLayer, allocator: std.mem.Allocator, comptime query: GroupQuery) !std.ArrayList(Entity.Type) {
    var entity_list = try self.mECSManagerGORef.GetGroup(allocator, query);
    self.FilterEntityByScene(&entity_list, allocator);
    return entity_list;
}
pub fn GetUUID(self: SceneLayer) u128 {
    return self.mECSManagerSCRef.GetComponent(SceneIDComponent, self.mSceneID).?.*.ID;
}
pub fn Duplicate(self: SceneLayer) !SceneLayer {
    return try self.mECSManagerSCRef.DuplicateEntity(self.mSceneID);
}

//for the entities in the scenes
pub fn CreateBlankEntity(self: SceneLayer) !Entity {
    const new_entity = Entity{ .mEntityID = try self.mECSManagerGORef.CreateEntity(), .mECSManagerRef = self.mECSManagerGORef };
    _ = try new_entity.AddComponent(EntitySceneComponent, .{ .SceneID = self.mSceneID });

    return new_entity;
}

pub fn CreateEntity(self: SceneLayer, engine_allocator: std.mem.Allocator) !Entity {
    return self.CreateEntityWithUUID(engine_allocator, try GenUUID());
}

pub fn CreateEntityWithUUID(self: SceneLayer, engine_allocator: std.mem.Allocator, uuid: u64) !Entity {
    const e = Entity{ .mEntityID = try self.mECSManagerGORef.CreateEntity(), .mECSManagerRef = self.mECSManagerGORef };
    _ = try e.AddComponent(EntityIDComponent, .{ .ID = uuid });
    _ = try e.AddComponent(EntitySceneComponent, .{ .SceneID = self.mSceneID });

    const new_name_component = try e.AddComponent(EntityNameComponent, .{ .mAllocator = engine_allocator });
    _ = try new_name_component.mName.writer(new_name_component.mAllocator).write("Unnamed Entity");

    _ = try e.AddComponent(TransformComponent, null);

    return e;
}

pub fn Delete(self: SceneLayer, engine_context: *EngineContext) !void {
    try engine_context.mGameEventManager.Insert(.{ .ET_DestroySceneEvent = .{ .mSceneID = self.mSceneID } });
    try engine_context.mImguiEventManager.Insert(.{ .ET_DeleteSceneEvent = .{ .mScene = self } });
}

pub fn AddBlankChildEntity(self: SceneLayer, parent_entity: Entity) !Entity {
    const new_entity_id = try self.mECSManagerGORef.AddChild(parent_entity.mEntityID);
    const child_entity = Entity{ .mEntityID = new_entity_id, .mECSManagerRef = self.mECSManagerGORef };

    _ = try child_entity.AddComponent(EntitySceneComponent, .{ .SceneID = self.mSceneID });

    return child_entity;
}

pub fn AddChildEntity(self: SceneLayer, parent_entity: Entity) !Entity {
    const new_entity_id = try self.mECSManagerGORef.AddChild(parent_entity.mEntityID);
    const child_entity = Entity{ .mEntityID = new_entity_id, .mECSManagerRef = self.mECSManagerGORef };

    _ = try child_entity.AddComponent(EntityIDComponent, .{ .ID = try GenUUID() });
    _ = try child_entity.AddComponent(EntitySceneComponent, .{ .SceneID = self.mSceneID });

    const new_name_component = try child_entity.AddComponent(EntityNameComponent, .{ .mAllocator = child_entity.GetECSAllocator() });
    _ = try new_name_component.mName.writer(new_name_component.mAllocator).write("Unnamed Entity");

    _ = try child_entity.AddComponent(TransformComponent, null);

    return child_entity;
}

pub fn DuplicateEntity(self: SceneLayer, original_entity: Entity) !Entity {
    const new_entity = Entity{ .mEntityID = try self.mECSManagerGORef.DuplicateEntity(original_entity.mEntityID), .mSceneLayerRef = self.mECSManagerGORef };
    return new_entity;
}

pub fn FilterEntityByScene(self: SceneLayer, list_allocator: std.mem.Allocator, entity_result_list: *std.ArrayList(Entity.Type)) void {
    if (entity_result_list.items.len == 0) return;

    var end_index: usize = entity_result_list.items.len;
    var i: usize = 0;

    while (i < end_index) {
        const entity_scene_component = self.mECSManagerGORef.GetComponent(EntitySceneComponent, entity_result_list.items[i]).?;
        if (entity_scene_component.SceneID != self.mSceneID) {
            entity_result_list.items[i] = entity_result_list.items[end_index - 1];
            end_index -= 1;
        } else {
            i += 1;
        }
    }

    entity_result_list.shrinkAndFree(list_allocator, end_index);
}

pub fn FilterEntityScriptsByScene(self: SceneLayer, list_allocator: std.mem.Allocator, scripts_result_list: *std.ArrayList(Entity.Type)) void {
    if (scripts_result_list.items.len == 0) return;

    var end_index: usize = scripts_result_list.items.len;
    var i: usize = 0;

    while (i < end_index) {
        const entity_script_component = self.mECSManagerGORef.GetComponent(EntityScriptComponent, scripts_result_list.items[i]).?;
        const parent_scene_component = self.mECSManagerGORef.GetComponent(EntitySceneComponent, entity_script_component.mParent).?;
        if (parent_scene_component.SceneID != self.mSceneID) {
            scripts_result_list.items[i] = scripts_result_list.items[end_index - 1];
            end_index -= 1;
        } else {
            i += 1;
        }
    }

    scripts_result_list.shrinkAndFree(list_allocator, end_index);
}

pub fn FilterSceneScriptsByScene(self: SceneLayer, list_allocator: std.mem.Allocator, scripts_result_list: *std.ArrayList(Entity.Type)) void {
    if (scripts_result_list.items.len == 0) return;

    var end_index: usize = scripts_result_list.items.len;
    var i: usize = 0;

    while (i < end_index) {
        const scene_script_component = self.mECSManagerSCRef.GetComponent(SceneScriptComponent, scripts_result_list.items[i]).?;
        if (scene_script_component.mParent != self.mSceneID) {
            scripts_result_list.items[i] = scripts_result_list.items[end_index - 1];
            end_index -= 1;
        } else {
            i += 1;
        }
    }

    scripts_result_list.shrinkAndFree(list_allocator, end_index);
}

pub fn EntityListDifference(self: SceneLayer, allocator: std.mem.Allocator, result: *std.ArrayList(Entity.Type), list2: std.ArrayList(Entity.Type)) !void {
    try self.mECSManagerGORef.EntityListDifference(result, list2, allocator);
}

pub fn GetEntityECSAllocator(self: SceneLayer) std.mem.Allocator {
    return self.mECSManagerGORef.GetECSAllocator();
}
