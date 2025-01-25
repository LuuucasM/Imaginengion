const std = @import("std");
const GetUUID = @import("../Core/UUID.zig").GenUUID;
const ArraySet = @import("../Vendor/ziglang-set/src/array_hash_set/managed.zig").ArraySetManaged;
const EntityManager = @This();

pub const NullEntity: u32 = ~0;

var NextID: u32 = 0;

_IDsInUse: ArraySet(u32),
_IDsRemoved: std.ArrayList(u32),

pub fn Init(ECSAllocator: std.mem.Allocator) EntityManager {
    return EntityManager{
        ._IDsInUse = ArraySet(u32).init(ECSAllocator),
        ._IDsRemoved = std.ArrayList(u32).init(ECSAllocator),
    };
}

pub fn Deinit(self: *EntityManager) void {
    self._IDsInUse.deinit();
    self._IDsRemoved.deinit();
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

pub fn GetAllEntities(self: EntityManager) ArraySet(u32) {
    return self._IDsInUse;
}
