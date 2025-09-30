const std = @import("std");
const ECSEventCategory = @import("ECSEvent.zig").ECSEventCategory;
const Tracy = @import("../Core/Tracy.zig");

pub fn ECSEventManager(entity_t: type, comptime component_types_size: usize) type {
    return struct {
        const Self = @This();
        const ECSEvent = @import("ECSEvent.zig").ECSEvent(entity_t);
        const ECSManager = @import("ECSManager.zig").ECSManager(entity_t, component_types_size);

        mDestroyEntities: std.ArrayList(ECSEvent) = .{},
        mCleanMultiEntities: std.ArrayList(ECSEvent) = .{},
        mAllocator: std.mem.Allocator,

        pub fn Init(allocator: std.mem.Allocator) !Self {
            return Self{
                .mAllocator = allocator,
            };
        }

        pub fn Deinit(self: Self) void {
            self.mDestroyEntities.deinit(self.mAllocator);
            self.mCleanMultiEntities.deinit(self.mAllocator);
        }

        pub fn Insert(self: Self, event: ECSEvent) !void {
            const zone = Tracy.ZoneInit("ECS Insert Events", @src());
            defer zone.Deinit();
            switch (event.GetEventCategory()) {
                .EC_DestroyEntities => try self.mDestroyEntities.append(self.mAllocator, event),
                .EC_CleanMultiEntities => try self.mCleanMultiEntities.append(self.mAllocator, event),
                else => @panic("Default Events are not allowed!\n"),
            }
        }

        pub fn ProcessEvents(self: Self, ecs_manager: ECSManager, eventCategory: ECSEventCategory) !void {
            const zone = Tracy.ZoneInit("ECS ProcessEvents", @src());
            defer zone.Deinit();
            const array = switch (eventCategory) {
                .EC_DestroyEntities => self.mDestroyEntities,
                .EC_CleanMultiEntities => self.mCleanMultiEntities,
                else => @panic("Default Events are not allowed!\n"),
            };

            for (array.items) |event| {
                switch (event) {
                    .ET_DestroyEntity => |e| try ecs_manager._InternalDestroyEntity(e.mEntityID),
                    .ET_CleanMultiEntity => |e| try ecs_manager._InternalDestroyMultiEntity(e.mEntityID),
                }
            }
        }

        pub fn EventsReset(self: Self) void {
            const zone = Tracy.ZoneInit("ECS Event Reset", @src());
            defer zone.Deinit();
            _ = self.mDestroyEntities.clearAndFree(self.mAllocator);
            _ = self.mCleanMultiEntities.clearAndFree(self.mAllocator);
        }
    };
}
