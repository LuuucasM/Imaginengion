const std = @import("std");
const GetUUID = @import("../Core/UUID.zig").GenUUID;
const Set = @import("../Vendor/ziglang-set/src/hash_set/managed.zig").HashSetManaged;
const EntityManager = @This();

pub const NullEntity: u32 = ~0;

var NextID: u32 = 0;

_IDsInUse: Set(u32),
_IDsRemoved: std.ArrayList(u32),
var EntityGPA: std.heap.GeneralPurposeAllocator(.{}) = std.heap.GeneralPurposeAllocator(.{}){},

pub fn Init() EntityManager {
    return EntityManager{
        ._IDsInUse = Set(u32).init(EntityGPA.allocator()),
        ._IDsRemoved = std.ArrayList(u32).init(EntityGPA.allocator()),
    };
}

pub fn Deinit(self: *EntityManager) void {
    self._IDsInUse.deinit();
    self._IDsRemoved.deinit();
    _ = self._EntityGPA.deinit();
}

pub fn CreateEntity(self: *EntityManager) !u32 {
    if (self._IDsRemoved.items.len != 0) {
        const new_id = self._IDsRemoved.pop();
        _ = try self._IDsInUse.add(new_id);
        return new_id;
    } else {
        const new_id = NextID;
        NextID += 1;
        _ = try self._IDsInUse.add(new_id);
        return new_id;
    }
}

pub fn DestroyEntity(self: *EntityManager, entityID: u32) !void {
    if (self._IDsInUse.remove(entityID) == true) {
        try self._IDsRemoved.append(entityID);
    }
}

pub fn GetAllEntities(self: EntityManager) *Set(u32) {
    return &self._IDsInUse;
}
