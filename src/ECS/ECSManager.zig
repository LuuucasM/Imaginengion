const std = @import("std");
const EntityManager = @import("EntityManager.zig");
const ComponentManager = @import("ComponentManager.zig");
const SystemManager = @import("SystemManager.zig");
const ECSManager = @This();

_EntityManager: EntityManager = .{},
_ComponentManager: ComponentManager = .{},
_SystemManager: SystemManager = .{},

pub fn Init(self: *ECSManager) !void {
    self._EntityManager.Init();
    try self._ComponentManager.Init();
    try self._SystemManager.Init();
}

pub fn Deinit(self: *ECSManager) void {
    self._EntityManager.Deinit();
    self._ComponentManager.Deinit();
    self._SystemManager.Deinit();
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

//-----------System Manager------------
pub fn SystemOnUpdate(self: ECSManager, comptime SystemType: type) !void {
    try self._SystemManager.SystemOnUpdate(SystemType);
}
