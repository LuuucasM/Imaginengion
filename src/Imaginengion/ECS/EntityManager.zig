const std = @import("std");
const GetUUID = @import("../Core/UUID.zig").GenUUID;
const ArraySet = @import("../Vendor/ziglang-set/src/array_hash_set/managed.zig").ArraySetManaged;

pub fn EntityManager(entity_t: type) type {
    return struct {
        const Self = @This();

        var NextID: entity_t = 0;

        _IDsInUse: ArraySet(entity_t),
        _IDsRemoved: std.ArrayList(entity_t),
        mIDsToRemove: std.ArrayList(entity_t),

        pub fn Init(ECSAllocator: std.mem.Allocator) Self {
            return Self{
                ._IDsInUse = ArraySet(entity_t).init(ECSAllocator),
                ._IDsRemoved = std.ArrayList(entity_t).init(ECSAllocator),
                .mIDsToRemove = std.ArrayList(entity_t).init(ECSAllocator),
            };
        }

        pub fn Deinit(self: *Self) void {
            self._IDsInUse.deinit();
            self._IDsRemoved.deinit();
            self.mIDsToRemove.deinit();
        }

        pub fn clearAndFree(self: *Self) void {
            self._IDsInUse.clearAndFree();
            self._IDsRemoved.clearAndFree();
            self.mIDsToRemove.clearAndFree();
        }

        pub fn CreateEntity(self: *Self) !entity_t {
            if (self._IDsRemoved.items.len != 0) {
                const new_id = self._IDsRemoved.pop().?;
                _ = try self._IDsInUse.add(new_id);
                return new_id;
            } else {
                const new_id = NextID;
                NextID += 1;
                _ = try self._IDsInUse.add(new_id);
                return new_id;
            }
        }

        pub fn DestroyEntity(self: *Self, entityID: entity_t) !void {
            _ = self._IDsInUse.remove(entityID);
            try self._IDsRemoved.append(entityID);
        }

        pub fn GetAllEntities(self: Self) ArraySet(entity_t) {
            return self._IDsInUse;
        }

        pub fn SetToDestroy(self: *Self, entityID: entity_t) !void {
            std.debug.assert(self._IDsInUse.contains(entityID));
            try self.mIDsToRemove.append(entityID);
        }
    };
}
