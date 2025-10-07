const std = @import("std");
const ECSEventCategory = @import("ECSEvent.zig").ECSEventCategory;
const Tracy = @import("../Core/Tracy.zig");

pub fn ECSEventManager(entity_t: type) type {
    return struct {
        const Self = @This();
        const ECSEvent = @import("ECSEvent.zig").ECSEvent(entity_t);

        pub const Iterator = struct {
            mList: std.ArrayList(ECSEvent),
            mIndex: usize,
            pub fn Next(self: *Iterator) ?ECSEvent {
                if (self.mIndex >= self.mList.items.len) return null;
                const event = self.mList.items[self.mIndex];
                self.mIndex += 1;
                return event;
            }
        };

        mRemoveObj: std.ArrayList(ECSEvent) = .{},
        mAllocator: std.mem.Allocator,

        pub fn Init(allocator: std.mem.Allocator) !Self {
            return Self{
                .mAllocator = allocator,
            };
        }

        pub fn Deinit(self: *Self) void {
            self.mRemoveObj.deinit(self.mAllocator);
        }

        pub fn Insert(self: *Self, event: ECSEvent) !void {
            const zone = Tracy.ZoneInit("ECS Insert Events", @src());
            defer zone.Deinit();
            switch (event.GetEventCategory()) {
                .EC_RemoveObj => try self.mRemoveObj.append(self.mAllocator, event),
                else => @panic("Default Events are not allowed!\n"),
            }
        }
        pub fn GetEventsIteartor(self: Self, eventCategory: ECSEventCategory) Iterator {
            const zone = Tracy.ZoneInit("ECS GetEventsIterator", @src());
            defer zone.Deinit();
            return switch (eventCategory) {
                .EC_RemoveObj => Iterator{
                    .mList = self.mRemoveObj,
                    .mIndex = 0,
                },
                else => @panic("Default Events are not allowed!\n"),
            };
        }

        pub fn ClearEvents(self: *Self, event_category: ECSEventCategory) void {
            switch (event_category) {
                .EC_RemoveObj => self.mRemoveObj.clearAndFree(self.mAllocator),
                else => @panic("default event is not allowed\n"),
            }
        }
    };
}
