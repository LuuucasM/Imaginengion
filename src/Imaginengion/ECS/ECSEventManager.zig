const std = @import("std");
const ECSEventCategory = @import("ECSEvent.zig").ECSEventCategory;
const Tracy = @import("../Core/Tracy.zig");

pub fn ECSEventManager(entity_t: type) type {
    return struct {
        const Self = @This();
        const ECSEvent = @import("ECSEvent.zig").ECSEvent(entity_t);

        mDestroyEntities: std.ArrayList(ECSEvent) = .{},
        mCleanMultiEntities: std.ArrayList(ECSEvent) = .{},

        var EventGPA = std.heap.DebugAllocator(.{}).init;
        const EventAllocator = EventGPA.allocator();

        pub fn Init() !ECSEventManager {
            return ECSEventManager{};
        }

        pub fn Deinit(self: ECSEventManager) void {
            self.mDestroyEntities.deinit(EventAllocator);
            _ = EventGPA.deinit();
        }

        pub fn Insert(self: ECSEventManager, event: ECSEvent) !void {
            const zone = Tracy.ZoneInit("ECS Insert Events", @src());
            defer zone.Deinit();
            switch (event.GetEventCategory()) {
                .EC_DestroyEntities => try self.mDestroyEntities.append(EventAllocator, event),
                .EC_CleanMultiEntities => try self.mCleanMultiEntities.append(EventAllocator, event),
                else => @panic("Default Events are not allowed!\n"),
            }
        }

        pub fn ProcessEvents(self: ECSEventManager, eventCategory: ECSEventCategory) !void {
            const zone = Tracy.ZoneInit("ECS ProcessEvents", @src());
            defer zone.Deinit();
            const array = switch (eventCategory) {
                .EC_DestroyEntities => self.mDestroyEntities,
                .EC_CleanMultiEntities => self.mCleanMultiEntities,
                else => @panic("Default Events are not allowed!\n"),
            };

            for (array.items) |event| {
                switch (event) {
                    .EC_DestroyEntities => |e| try self.mECSManager._InternalDestroyEntity(e),
                    .EC_CleanMultiEntities => |e| try self.mECSManager._InternalDestroyMultiEntity(e),
                }
            }
        }

        pub fn EventsReset(self: ECSEventManager) void {
            const zone = Tracy.ZoneInit("ECS Event Reset", @src());
            defer zone.Deinit();
            _ = self.mDestroyEntities.clearAndFree(EventAllocator);
        }
    };
}
