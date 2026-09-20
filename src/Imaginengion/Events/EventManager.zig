const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const builtin = @import("builtin");

pub const ClearMode = enum {
    ClearAndFree,
    ClearRetainingCapacity,
};

pub const EventResult = enum {
    Continue,
    Consume,
};

pub fn EventManager(EventData: type) type {
    return struct {
        pub const CallbackList = std.DoublyLinkedList;

        pub const EventCallback = struct {
            mCtx: *anyopaque,
            mCallbackFn: *const fn (*anyopaque, *EngineContext, *const EventData.EventT) anyerror!EventResult,
            mNode: CallbackList.Node = .{},
        };

        pub const EventType = EventData.EventT;

        const Self = @This();
        pub const EventsArrayT = std.EnumArray(EventData.EventCategories, std.ArrayList(EventData.EventT));

        pub const empty: Self = .{
            .mEventsArray = EventsArrayT.initFill(.empty),
        };

        mEventsArray: EventsArrayT,

        pub fn Deinit(self: *Self, engine_allocator: std.mem.Allocator) void {
            var iter = self.mEventsArray.iterator();
            while (iter.next()) |entry| {
                entry.value.deinit(engine_allocator);
            }
        }

        pub fn Insert(self: *Self, engine_allocator: std.mem.Allocator, comptime category: EventData.EventCategories, event: EventData.EventT) !void {
            try self.mEventsArray.getPtr(category).append(engine_allocator, event);
        }

        /// Copies every queued event into `other`, which must be empty.
        /// Events are plain values, so this only makes sense when the copy shares the ids they name.
        pub fn CopyInto(self: *Self, engine_allocator: std.mem.Allocator, other: *Self) !void {
            errdefer other.EventsReset(engine_allocator, .ClearAndFree);

            var iter = self.mEventsArray.iterator();
            while (iter.next()) |entry| {
                const other_events = other.mEventsArray.getPtr(entry.key);
                std.debug.assert(other_events.items.len == 0);
                try other_events.appendSlice(engine_allocator, entry.value.items);
            }
        }

        /// Process events for a specific phase, in queue order: each event goes to every callback in list order.
        /// A callback may queue more events of this category while running; they are appended and processed by
        /// this same call, which is why the loop indexes the list instead of holding a slice of it.
        /// The EventResult a callback returns is currently ignored, so .Consume does not stop later callbacks.
        /// Clearing the events is up to the caller (EventsReset / ClearCategory).
        pub fn ProcessCategory(self: *Self, comptime category: EventData.EventCategories, engine_context: *EngineContext, callback_list: std.DoublyLinkedList) !void {
            var event_ind: usize = 0;
            while (event_ind < self.mEventsArray.getPtr(category).items.len) : (event_ind += 1) {
                // by value: appending to the list can move it while the callbacks below are running
                const event = self.mEventsArray.getPtr(category).items[event_ind];

                var iter = callback_list.first;
                while (iter) |node| : (iter = node.next) {
                    const event_callback: *EventCallback = @fieldParentPtr("mNode", node);
                    _ = try event_callback.mCallbackFn(event_callback.mCtx, engine_context, &event);
                }
            }
        }

        /// Same as EventsReset but for a single category, for managers that process one category at a time.
        pub fn ClearCategory(self: *Self, engine_allocator: std.mem.Allocator, comptime category: EventData.EventCategories, clear_mode: ClearMode) void {
            switch (clear_mode) {
                .ClearAndFree => self.mEventsArray.getPtr(category).clearAndFree(engine_allocator),
                .ClearRetainingCapacity => self.mEventsArray.getPtr(category).clearRetainingCapacity(),
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
