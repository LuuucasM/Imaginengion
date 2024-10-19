const std = @import("std");
const EntityManager = @import("EntityManager.zig");
const ComponentManager = @import("ComponentManager.zig");
const SystemManager = @import("SystemManager.zig");
const ECSManager = @This();

_EntityManager: EntityManager,
_ComponentManager: ComponentManager,
_SystemManager: SystemManager,
mECSAllocator: std.mem.Allocator,

pub fn Init(ECSAllocator: std.mem.Allocator) !ECSManager {
    return ECSManager{
        ._EntityManager = EntityManager.Init(ECSAllocator),
        ._ComponentManager = try ComponentManager.Init(ECSAllocator),
        ._SystemManager = try SystemManager.Init(ECSAllocator),
        .mECSAllocator = ECSAllocator,
    };
}

pub fn Deinit(self: *ECSManager) void {
    self._EntityManager.Deinit();
    self._ComponentManager.Deinit(self.mECSAllocator);
    self._SystemManager.Deinit(self.mECSAllocator);
}

//---------------EntityManager--------------
pub fn CreateEntity(self: *ECSManager) !u32 {
    const entityID = try self._EntityManager.CreateEntity();
    try self._ComponentManager.CreateEntity(entityID);
    self._SystemManager.CreateEntity(entityID);
    return entityID;
}

pub fn DestroyEntity(self: *ECSManager, entityID: u32) !void {
    try self._ComponentManager.DestroyEntity(entityID);
    self._SystemManager.DestroyEntity(entityID);
    try self._EntityManager.DestroyEntity(entityID);
}

pub fn GetAllEntities(self: ECSManager) std.AutoArrayHashMap(u32, EntityManager.ComponentMaskType) {
    return self._EntityManager.GetAllEntities();
}

pub fn DuplicateEntity(self: *ECSManager, original_entity_id: u32) !u32 {
    const new_entity_id = try self.CreateEntity();
    self._ComponentManager.DuplicateEntity(original_entity_id, new_entity_id);
    self._SystemManager.DuplicateEntity(original_entity_id, new_entity_id);
    return new_entity_id;
}

//components
pub fn AddComponent(self: *ECSManager, comptime ComponentType: type, entityID: u32, component: ComponentType) !*ComponentType {
    const new_component = try self._ComponentManager.AddComponent(ComponentType, entityID, component);
    try self._SystemManager.AddComponent(ComponentType, entityID);
    return new_component;
}

pub fn RemoveComponent(self: *ECSManager, comptime ComponentType: type, entityID: u32) !void {
    try self._ComponentManager.RemoveComponent(ComponentType, entityID);
    self._SystemManager.RemoveComponent(ComponentType, entityID);
}

pub fn HasComponent(self: ECSManager, comptime ComponentType: type, entityID: u32) bool {
    return self._ComponentManager.HasComponent(ComponentType, entityID);
}

pub fn GetComponent(self: ECSManager, comptime ComponentType: type, entityID: u32) *ComponentType {
    return self._ComponentManager.GetComponent(ComponentType, entityID);
}

pub fn Stringify(self: ECSManager, out: *std.ArrayList(u8), entityID: u32) !void {
    try self._ComponentManager.Stringify(out, entityID);
}

//-----------System Manager------------
pub fn SystemOnUpdate(self: ECSManager, comptime SystemType: type) void {
    try self._SystemManager.SystemOnUpdate(SystemType);
}
