const std = @import("std");
const GetUUID = @import("../Core/UUID.zig").GenUUID;
const Set = @import("../Vendor/ziglang-set/src/hash_set/managed.zig").HashSetManaged;
const EntityManager = @This();

_IDsInUse: Set(u128) = undefined,
_IDsRemoved: Set(u128) = undefined,
_Allocator: std.mem.Allocator = std.heap.page_allocator,

pub fn Init(self: *EntityManager) void {
    self._IDsInUse = Set(u128).init(self._Allocator);
    self._IDsRemoved = Set(u128).init(self._Allocator);
}

pub fn Deinit(self: EntityManager) void {
    self._IDsInUse.deinit();
    self._IDsRemoved.deinit();
}

pub fn CreateEntity(self: *EntityManager) !u64 {
    if (self._IDsRemoved.isEmpty() == false) {
        var iter = self._IDsRemoved.iterator();
        const first = iter.next();
        const id = first.?.*;
        _ = try self._IDsInUse.add(id);
        return id;
    } else {
        const new_id = try GetUUID();
        _ = try self._IDsInUse.add(new_id);
        return new_id;
    }
}

pub fn DestroyEntity(self: *EntityManager, entityID: u64) !void {
    if (self._IDsInUse.remove(entityID) == true) {
        _ = try self._IDsRemoved.add(entityID);
    }
}
