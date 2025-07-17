const std = @import("std");
const EntityManager = @import("EntityManager.zig").EntityManager;
const ComponentManager = @import("ComponentManager.zig").ComponentManager;
const GroupQuery = @import("ComponentManager.zig").GroupQuery;
const ArraySet = @import("../Vendor/ziglang-set/src/array_hash_set/managed.zig").ArraySetManaged;
const Tracy = @import("../Core/Tracy.zig");

pub fn ECSManager(entity_t: type, comptime component_types_size: usize) type {
    return struct {
        const Self = @This();
        mEntityManager: EntityManager(entity_t),
        mComponentManager: ComponentManager(entity_t, component_types_size),
        mECSAllocator: std.mem.Allocator,

        pub fn Init(ECSAllocator: std.mem.Allocator, comptime components_types: []const type) !Self {
            return Self{
                .mEntityManager = EntityManager(entity_t).Init(ECSAllocator),
                .mComponentManager = try ComponentManager(entity_t, component_types_size).Init(ECSAllocator, components_types),
                .mECSAllocator = ECSAllocator,
            };
        }

        pub fn Deinit(self: *Self) void {
            self.mEntityManager.Deinit();
            self.mComponentManager.Deinit();
        }

        pub fn clearAndFree(self: *Self) void {
            self.mEntityManager.clearAndFree();
            self.mComponentManager.clearAndFree();
        }

        //---------------EntityManager--------------
        pub fn CreateEntity(self: *Self) !entity_t {
            const entityID = try self.mEntityManager.CreateEntity();
            try self.mComponentManager.CreateEntity(entityID);
            return entityID;
        }

        pub fn DestroyEntity(self: *Self, entityID: entity_t) !void {
            try self.mEntityManager.SetToDestroy(entityID);
        }

        pub fn ProcessDestroyedEntities(self: *Self) !void {
            const zone = Tracy.ZoneInit("ECSM ProcessDestroyedEntities", @src());
            defer zone.Deinit();
            for (self.mEntityManager.mIDsToRemove.items) |entity_id| {
                try self.mEntityManager.DestroyEntity(entity_id);
                try self.mComponentManager.DestroyEntity(entity_id);
            }
            self.mEntityManager.mIDsToRemove.clearAndFree();
        }

        pub fn GetAllEntities(self: Self) ArraySet(entity_t) {
            return self.mEntityManager.GetAllEntities();
        }

        pub fn DuplicateEntity(self: *Self, original_entity_id: entity_t) !entity_t {
            const new_entity_id = try self.CreateEntity();
            self.mComponentManager.DuplicateEntity(original_entity_id, new_entity_id);
            return new_entity_id;
        }

        //for getting groups of entities
        pub fn GetGroup(self: Self, comptime query: GroupQuery, allocator: std.mem.Allocator) !std.ArrayList(entity_t) {
            const zone = Tracy.ZoneInit("ECSM GetGroup", @src());
            defer zone.Deinit();
            return try self.mComponentManager.GetGroup(query, allocator);
        }

        pub fn EntityListDifference(self: Self, result: *std.ArrayList(entity_t), list2: std.ArrayList(entity_t), allocator: std.mem.Allocator) !void {
            try self.mComponentManager.EntityListDifference(result, list2, allocator);
        }

        pub fn EntityListUnion(self: Self, result: *std.ArrayList(entity_t), list2: std.ArrayList(entity_t), allocator: std.mem.Allocator) !void {
            try self.mComponentManager.EntityListUnion(result, list2, allocator);
        }

        pub fn EntityListIntersection(self: Self, result: *std.ArrayList(entity_t), list2: std.ArrayList(entity_t), allocator: std.mem.Allocator) !void {
            try self.mComponentManager.EntityListIntersection(result, list2, allocator);
        }

        //components related functions
        pub fn AddComponent(self: *Self, comptime ComponentType: type, entityID: entity_t, component: ?ComponentType) !*ComponentType {
            const new_component = try self.mComponentManager.AddComponent(ComponentType, entityID, component);
            return new_component;
        }

        pub fn RemoveComponent(self: *Self, comptime ComponentType: type, entityID: entity_t) !void {
            try self.mComponentManager.RemoveComponent(ComponentType, entityID);
        }

        pub fn HasComponent(self: Self, comptime ComponentType: type, entityID: entity_t) bool {
            const zone = Tracy.ZoneInit("ECSM HasComponent", @src());
            defer zone.Deinit();
            return self.mComponentManager.HasComponent(ComponentType, entityID);
        }

        pub fn GetComponent(self: Self, comptime ComponentType: type, entityID: entity_t) *ComponentType {
            const zone = Tracy.ZoneInit("ECSM GetComponent", @src());
            defer zone.Deinit();
            return self.mComponentManager.GetComponent(ComponentType, entityID);
        }
    };
}
