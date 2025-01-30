const std = @import("std");
const EntityManager = @import("EntityManager.zig");
const ComponentManager = @import("ComponentManager.zig");
const Filter = ComponentManager.Filter;
const GroupQuery = ComponentManager.GroupQuery;
const SystemManager = @import("SystemManager.zig");
const ArraySet = @import("../Vendor/ziglang-set/src/array_hash_set/managed.zig").ArraySetManaged;
const ECSManager = @This();

mEntityManager: EntityManager,
mComponentManager: ComponentManager,
mSystemManager: SystemManager,
mECSAllocator: std.mem.Allocator,

pub fn Init(ECSAllocator: std.mem.Allocator, comptime components_types: []const type, system_types: []const type) !ECSManager {
    return ECSManager{
        .mEntityManager = EntityManager.Init(ECSAllocator),
        .mComponentManager = try ComponentManager.Init(ECSAllocator, components_types),
        .mSystemManager = try SystemManager.Init(ECSAllocator, system_types),
        .mECSAllocator = ECSAllocator,
    };
}

pub fn Deinit(self: *ECSManager) void {
    self.mEntityManager.Deinit();
    self.mComponentManager.Deinit();
    self.mSystemManager.Deinit();
}

//---------------EntityManager--------------
pub fn CreateEntity(self: *ECSManager) !u32 {
    const entityID = try self.mEntityManager.CreateEntity();
    try self.mComponentManager.CreateEntity(entityID);
    self.mSystemManager.CreateEntity(entityID);
    return entityID;
}

pub fn DestroyEntity(self: *ECSManager, entityID: u32) !void {
    try self.mComponentManager.DestroyEntity(entityID);
    self.mSystemManager.DestroyEntity(entityID);
    try self.mEntityManager.DestroyEntity(entityID);
}

pub fn GetAllEntities(self: ECSManager) ArraySet(u32) {
    return self.mEntityManager.GetAllEntities();
}

pub fn DuplicateEntity(self: *ECSManager, original_entity_id: u32) !u32 {
    const new_entity_id = try self.CreateEntity();
    self.mComponentManager.DuplicateEntity(original_entity_id, new_entity_id);
    self.mSystemManager.DuplicateEntity(original_entity_id, new_entity_id);
    return new_entity_id;
}

//components
pub fn AddComponent(self: *ECSManager, comptime ComponentType: type, entityID: u32, component: ?ComponentType) !*ComponentType {
    const new_component = try self.mComponentManager.AddComponent(ComponentType, entityID, component);
    try self.mSystemManager.AddComponent(self.mComponentManager.mEntitySkipField.getValueBySparse(entityID).*, entityID);
    return new_component;
}

pub fn RemoveComponent(self: *ECSManager, comptime ComponentType: type, entityID: u32) !void {
    try self.mComponentManager.RemoveComponent(ComponentType, entityID);
    self.mSystemManager.RemoveComponent(@as(self.mEComponents, @enumFromInt(ComponentType.Ind)), self.mComponentManager.mEntitySkipField.getValueBySparse(entityID).*, entityID);
}

pub fn HasComponent(self: ECSManager, comptime ComponentType: type, entityID: u32) bool {
    return self.mComponentManager.HasComponent(ComponentType, entityID);
}

pub fn GetComponent(self: ECSManager, comptime ComponentType: type, entityID: u32) *ComponentType {
    return self.mComponentManager.GetComponent(ComponentType, entityID);
}

pub fn GetQuery(self: ECSManager, query: GroupQuery, allocator: std.mem.Allocator) !std.ArrayList(u32) {
    return try self.mComponentManager.GetQuery(query, allocator);
}

//-----------System Manager------------
pub fn SystemOnUpdate(self: *ECSManager, comptime SystemType: type) !void {
    try self.mSystemManager.SystemOnUpdate(SystemType, self.mComponentManager);
}
