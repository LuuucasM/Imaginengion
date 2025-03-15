const std = @import("std");
const EntityManager = @import("EntityManager.zig");
const ComponentManager = @import("ComponentManager.zig");
const Filter = ComponentManager.Filter;
const GroupQuery = ComponentManager.GroupQuery;
const ArraySet = @import("../Vendor/ziglang-set/src/array_hash_set/managed.zig").ArraySetManaged;
const ECSManager = @This();

mEntityManager: EntityManager,
mComponentManager: ComponentManager,
mECSAllocator: std.mem.Allocator,

pub fn Init(ECSAllocator: std.mem.Allocator, comptime components_types: []const type) !ECSManager {
    return ECSManager{
        .mEntityManager = EntityManager.Init(ECSAllocator),
        .mComponentManager = try ComponentManager.Init(ECSAllocator, components_types),
        .mECSAllocator = ECSAllocator,
    };
}

pub fn Deinit(self: *ECSManager) void {
    self.mEntityManager.Deinit();
    self.mComponentManager.Deinit();
}

pub fn clearAndFree(self: *ECSManager) void {
    self.mEntityManager.clearAndFree();
    self.mComponentManager.clearAndFree();
}

//---------------EntityManager--------------
pub fn CreateEntity(self: *ECSManager) !u32 {
    const entityID = try self.mEntityManager.CreateEntity();
    try self.mComponentManager.CreateEntity(entityID);
    return entityID;
}

pub fn DestroyEntity(self: *ECSManager, entityID: u32) !void {
    try self.mEntityManager.SetToDestroy(entityID);
}

pub fn ProcessDestroyedEntities(self: *ECSManager) !void {
    for (self.mEntityManager.mIDsToRemove.items) |entity_id| {
        try self.mEntityManager.DestroyEntity(entity_id);
        try self.mComponentManager.DestroyEntity(entity_id);
    }
    self.mEntityManager.mIDsToRemove.clearAndFree();
}

pub fn GetAllEntities(self: ECSManager) ArraySet(u32) {
    return self.mEntityManager.GetAllEntities();
}

pub fn DuplicateEntity(self: *ECSManager, original_entity_id: u32) !u32 {
    const new_entity_id = try self.CreateEntity();
    self.mComponentManager.DuplicateEntity(original_entity_id, new_entity_id);
    return new_entity_id;
}

//components
pub fn AddComponent(self: *ECSManager, comptime ComponentType: type, entityID: u32, component: ?ComponentType) !*ComponentType {
    const new_component = try self.mComponentManager.AddComponent(ComponentType, entityID, component);
    return new_component;
}

pub fn RemoveComponent(self: *ECSManager, comptime ComponentType: type, entityID: u32) !void {
    try self.mComponentManager.RemoveComponent(ComponentType, entityID);
}

pub fn HasComponent(self: ECSManager, comptime ComponentType: type, entityID: u32) bool {
    return self.mComponentManager.HasComponent(ComponentType, entityID);
}

pub fn GetComponent(self: ECSManager, comptime ComponentType: type, entityID: u32) *ComponentType {
    return self.mComponentManager.GetComponent(ComponentType, entityID);
}

pub fn GetGroup(self: ECSManager, query: GroupQuery, allocator: std.mem.Allocator) !std.ArrayList(u32) {
    return try self.mComponentManager.GetGroup(query, allocator);
}

pub fn EntityListDifference(self: ECSManager, result: *std.ArrayList(u32), list2: std.ArrayList(u32), allocator: std.mem.Allocator) !void {
    try self.mComponentManager.EntityListDifference(result, list2, allocator);
}

pub fn EntityListUnion(self: ECSManager, result: *std.ArrayList(u32), list2: std.ArrayList(u32), allocator: std.mem.Allocator) !void {
    try self.mComponentManager.EntityListUnion(result, list2, allocator);
}

pub fn EntityListIntersection(self: ECSManager, result: *std.ArrayList(u32), list2: std.ArrayList(u32), allocator: std.mem.Allocator) !void {
    try self.mComponentManager.EntityListIntersection(result, list2, allocator);
}
