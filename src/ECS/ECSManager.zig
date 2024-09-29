const std = @import("std");
const EntityManager = @import("EntityManager.zig");
const ComponentManager = @import("ComponentManager.zig");
const SystemManager = @import("SystemManager.zig");
const ECS = @This();

_EntityManager: EntityManager,
_ComponentManager: ComponentManager,
_SystemManager: SystemManager,
_EngineAllocator: std.mem.Allocator,

pub fn Init(EngineAllocator: std.mem.Allocator) ECS {
    const ecs = try EngineAllocator.create(ECS);
    ecs.* = .{
        ._EngineAllocator = EngineAllocator,
    };
    return ecs;
}

pub fn Deinit(self: ECS) void {
    self._EngineAllocator.destroy(self);
}

//---------------EntityManager--------------
pub fn CreateEntity(self: ECS) u128 {
    return self._EntityManager.CreateEntity();
}

pub fn DestroyEntity(self: ECS, entityID: u128) void {
    self._EntityManager.DestroyEntity(entityID);
}

//-------------ComponentManager------------
pub fn RegisterComponent(self: ECS, comptime ComponentType: type) void {
    self._ComponentManager.RegisterComponent(ComponentType);
}

pub fn AddComponent(self: ECS, comptime ComponentType: type, entityID: u128, component: ComponentType) *ComponentType {
    return self._ComponentManager.AddComponent(ComponentType, entityID, component);
}

pub fn AddComponents(self: ECS, comptime ComponentTypes: anytype, entityID: u128, components: anytype) std.meta.Tuple(ComponentTypes) {
    return self._ComponentManager.AddComponents(ComponentTypes, entityID, components);
}

pub fn RemoveComponent(self: ECS, comptime ComponentType: type, entityID: u128) void {
    return self._ComponentManager.RemoveComponent(ComponentType, entityID);
}

pub fn RemoveComponents(self: ECS, comptime ComponentTypes: anytype, entityID: u128) void {
    return self._ComponentManager.RemoveComponents(ComponentTypes, entityID);
}

pub fn HasComponent(self: ECS, comptime ComponentType: type, entityID: u128) bool {
    return self._ComponentManager.HasComponent(ComponentType, entityID);
}

//-----------System Manager------------
pub fn RegisterSystem(self: ECS, comptime SystemType: type, comptime ComponentTypes: anytype) void {
    return self._SystemManager.RegisterSystem(SystemType, ComponentTypes);
}
pub fn SystemOnUpdate(self: ECS, comptime SystemType: type) void {
    return self._SystemManager.SystemOnUpdate(SystemType);
}
