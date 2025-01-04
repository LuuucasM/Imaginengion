const std = @import("std");
const assert = std.debug.assert;
const Event = @import("Event.zig").Event;
const EventCategory = @import("EventEnums.zig").EventCategory;
const EventType = @import("EventEnums.zig").EventType;
const Self = @This();

var EventManager: *Self = undefined;

_InputEventPool: std.ArrayList(Event),
_WindowEventPool: std.ArrayList(Event),
_EngineAllocator: std.mem.Allocator,
_EventCallback: *const fn (*Event) void,

var EventGPA = std.heap.GeneralPurposeAllocator(.{}){};

pub fn Init(EngineAllocator: std.mem.Allocator, eventCallback: fn (*Event) void) !void {
    EventManager = try EngineAllocator.create(Self);
    EventManager.* = .{
        ._InputEventPool = std.ArrayList(Event).init(EventGPA.allocator()),
        ._WindowEventPool = std.ArrayList(Event).init(EventGPA.allocator()),
        ._EngineAllocator = EngineAllocator,
        ._EventCallback = eventCallback,
    };
}

pub fn Deinit() void {
    EventManager._InputEventPool.deinit();
    EventManager._WindowEventPool.deinit();
    EventManager._EngineAllocator.destroy(EventManager);
    _ = EventGPA.deinit();
}

pub fn Insert(event: Event) !void {
    switch (event.GetEventCategory()) {
        .EC_Input => try EventManager._InputEventPool.append(event),
        .EC_Window => try EventManager._WindowEventPool.append(event),
    }
}

pub fn ProcessEvents(eventCategory: EventCategory) void {
    const array = switch (eventCategory) {
        .EC_Input => EventManager._InputEventPool,
        .EC_Window => EventManager._WindowEventPool,
    };

    for (array.items) |*event| {
        EventManager._EventCallback(event);
    }
}

pub fn EventsReset() void {
    //const capacity = std.heap.ArenaAllocator.ResetMode{ .retain_with_limit = 20 };
    _ = EventManager._InputEventPool.clearAndFree();
    _ = EventManager._WindowEventPool.clearAndFree();
}
