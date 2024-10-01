const std = @import("std");
const EntityManager = @import("EntityManager.zig");
const ComponentManager = @import("ComponentManager.zig");
const SystemManager = @import("SystemManager.zig");
const ECSManager = @This();

_EntityManager: EntityManager = .{},
_ComponentManager: ComponentManager = .{},
_SystemManager: SystemManager = .{},

pub fn Init(self: ECSManager) void {
    self._EntityManager.Init();
    self._ComponentManager.Init();
}

pub fn Deinit(self: ECS) void {
    self._EntityManager.Deinit();
    self._ComponentManager.Deinit();
}

//---------------EntityManager--------------
pub fn CreateEntity(self: *ECS) !u64 {
    return self._EntityManager.CreateEntity();
}

pub fn DestroyEntity(self: *ECS, entityID: u64) !void {
    try self._EntityManager.DestroyEntity(entityID);
}

//-------------ComponentManager------------
//so basically i am going to use sparce sets like EnTT does but
//components must be registered
//then i will save a 'skipfield' pattern for each registerd system so they can iterate over components
//as an entities components get added i will check to see if that entitys bitmap is the same as the systems
//if its in the system then just add 0 to the skipfield, else adjust the skipfield as needed
//then every frame we will try to organize one of the component
pub fn RegisterComponent(self: ECS, comptime ComponentType: type) !void {
    try self._ComponentManager.RegisterComponent(ComponentType);
}

pub fn AddComponent(self: ECS, comptime ComponentType: type, entityID: u64, component: ComponentType) *ComponentType {
    return self._ComponentManager.AddComponent(ComponentType, entityID, component);
}

pub fn RemoveComponent(self: ECS, comptime ComponentType: type, entityID: u64) void {
    return self._ComponentManager.RemoveComponent(ComponentType, entityID);
}

pub fn HasComponent(self: ECS, comptime ComponentType: type, entityID: u64) bool {
    return self._ComponentManager.HasComponent(ComponentType, entityID);
}

pub fn GetComponent(self: ECS, comptime ComponentType: type, entityID: u64) *ComponentType {
    return self._ComponentManager.GetComponent(ComponentType, entityID);
}

pub fn GetComponents(self: ECS, comptime ComponentTypes: anytype, entityID: u64) std.meta.Tuple(ComponentTypes) {
    return self._ComponentManager.GetComponents(ComponentTypes, entityID);
}

//-----------System Manager------------
pub fn RegisterSystem(self: ECS, comptime SystemType: type, comptime ComponentTypes: anytype) void {
    return self._SystemManager.RegisterSystem(SystemType, ComponentTypes);
}
pub fn SystemOnUpdate(self: ECS, comptime SystemType: type) void {
    return self._SystemManager.SystemOnUpdate(SystemType);
}
