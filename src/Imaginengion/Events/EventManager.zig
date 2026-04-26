const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const builtin = @import("builtin");

pub fn EventManager(EventCategoriesType: type, EventUnionType: type) type {
    return struct {
        pub const ClearMode = enum {
            ClearAndFree,
            ClearRetainingCapacity,
        };

        pub const CallbackList = std.DoublyLinkedList;

        pub const EventCallback = struct {
            mCtx: *anyopaque,
            mCallbackFn: *const fn (*anyopaque, *EngineContext, EventUnionType) anyerror!bool,
            mNode: CallbackList.Node = .{},
        };

        pub const EventType = EventUnionType;

        const Self = @This();
        pub const EventsArrayT = std.EnumArray(EventCategoriesType, std.ArrayList(EventUnionType));

        mEventsArray: EventsArrayT = EventsArrayT.initFill(.empty),

        pub fn Deinit(self: *Self, engine_allocator: std.mem.Allocator) void {
            var iter = self.mEventsArray.iterator();
            while (iter.next()) |entry| {
                entry.value.deinit(engine_allocator);
            }
        }

        pub fn Insert(self: *Self, engine_allocator: std.mem.Allocator, comptime category: EventCategoriesType, event: EventUnionType) !void {
            try self.mEventsArray.getPtr(category).append(engine_allocator, event);
        }

        /// Process events for a specific phase.
        /// If `callback_fn` returns `true`, the event is removed (swap-remove, order not preserved).
        pub fn ProcessCategory(self: *Self, comptime category: EventCategoriesType, engine_context: *EngineContext, callback_list: std.DoublyLinkedList) !void {
            const events = self.mEventsArray.get(category).items;

            var iter = callback_list.first;
            while (iter) |node| : (iter = node.next) {
                const event_callback: *EventCallback = @fieldParentPtr("mNode", node);
                for (events) |event| {
                    _ = try event_callback.mCallbackFn(event_callback.mCtx, engine_context, event);
                }
            }
        }

        pub fn EventsReset(self: *Self, engine_allocator: std.mem.Allocator, clear_mode: ClearMode) void {
            var iter = self.mEventsArray.iterator();
            while (iter.next()) |entry| {
                switch (clear_mode) {
                    .ClearAndFree => entry.value.clearAndFree(engine_allocator),
                    .ClearRetainingCapacity => entry.value.clearRetainingCapacity(),
                }
            }
        }
    };
}
