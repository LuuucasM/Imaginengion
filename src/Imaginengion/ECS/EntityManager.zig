const std = @import("std");
const ArraySet = @import("../Vendor/ziglang-set/src/array_hash_set/managed.zig").ArraySetManaged;

pub fn EntityManager(entity_t: type) type {
    return struct {
        const Self = @This();

        _NextID: entity_t = 0,
        _IDsInUse: ArraySet(entity_t) = undefined,
        _IDsRemoved: std.ArrayList(entity_t) = .{},
        mIDsToRemove: std.ArrayList(entity_t) = .{},

        pub fn Init(self: *Self, engine_allocator: std.mem.Allocator) void {
            self._IDsInUse = ArraySet(entity_t).init(engine_allocator);
        }

        pub fn Deinit(self: *Self, engine_allocator: std.mem.Allocator) void {
            self._IDsInUse.deinit();
            self._IDsRemoved.deinit(engine_allocator);
            self.mIDsToRemove.deinit(engine_allocator);
        }

        pub fn clearAndFree(self: *Self, engine_allocator: std.mem.Allocator) void {
            self._IDsInUse.clearAndFree();
            self._IDsRemoved.clearAndFree(engine_allocator);
            self.mIDsToRemove.clearAndFree(engine_allocator);
            self._NextID = 0;
        }

        pub fn CreateEntity(self: *Self) !entity_t {
            if (self._IDsRemoved.items.len > 0) {
                const new_id = self._IDsRemoved.pop().?;
                _ = try self._IDsInUse.add(new_id);
                return new_id;
            } else {
                const new_id = self._NextID;
                std.debug.assert(!self._IDsInUse.contains(new_id));
                std.debug.assert(self._NextID != std.math.maxInt(entity_t));

                self._NextID += 1;
                _ = try self._IDsInUse.add(new_id);
                return new_id;
            }
        }

        pub fn DestroyEntity(self: *Self, engine_allocator: std.mem.Allocator, entityID: entity_t) !void {
            _ = self._IDsInUse.remove(entityID);
            try self._IDsRemoved.append(engine_allocator, entityID);
        }

        pub fn GetAllEntities(self: Self) ArraySet(entity_t) {
            return self._IDsInUse;
        }
    };
}
