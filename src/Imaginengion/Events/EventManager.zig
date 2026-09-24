const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const builtin = @import("builtin");
const Tracy = @import("../Core/Tracy.zig");

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

        /// The one synchronous listener, set once at startup by EngineContext.SetSyncCallbacks.
        /// Null means nothing listens synchronously and Dispatch is a no-op. The ctx it points at
        /// is a member of Application, so it outlives this manager and never needs unregistering.
        mSyncCallback: ?EventCallback = null,

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
            const zone = Tracy.ZoneInit("EventManager::ProcessCategory(" ++ Tracy.ShortTypeName(EventData) ++ ", " ++ @tagName(category) ++ ")", @src());
            defer zone.Deinit();

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
            //counted after the loop because callbacks can queue more events of this category mid-pass
            zone.Value(event_ind);
        }

        /// Wraps `handler` on `ctx` into the type-erased callback this manager stores.
        /// `handler` may be generic (`event: anytype`): it is a comptime value here, and the call
        /// inside the thunk is what instantiates it with this manager's concrete event type. The
        /// thunk itself is concrete, which is what makes it storable as a function pointer.
        pub fn MakeCallback(comptime Ctx: type, comptime handler: anytype, ctx: *Ctx) EventCallback {
            return .{
                .mCtx = ctx,
                .mCallbackFn = struct {
                    fn thunk(ctx_ptr: *anyopaque, engine_context: *EngineContext, event: *const EventData.EventT) anyerror!EventResult {
                        return handler(@as(*Ctx, @ptrCast(@alignCast(ctx_ptr))), engine_context, event);
                    }
                }.thunk,
            };
        }

        /// Points this manager's synchronous listener at `handler` on `ctx`.
        pub fn SetSyncCallback(self: *Self, ctx: anytype, comptime handler: anytype) void {
            self.mSyncCallback = MakeCallback(@typeInfo(@TypeOf(ctx)).pointer.child, handler, ctx);
        }

        /// Synchronous counterpart to ProcessCategory: hands `event` to the sync listener right now
        /// and returns its result, so .Consume is meaningful here (the deferred path ignores it).
        /// Nothing is queued and nothing is stored, so `event` is only valid for the duration of
        /// this call: a listener that needs it afterwards must copy it.
        pub fn Dispatch(self: *Self, engine_context: *EngineContext, event: EventData.EventT) anyerror!EventResult {
            const callback = self.mSyncCallback orelse return .Continue;
            return callback.mCallbackFn(callback.mCtx, engine_context, &event);
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
