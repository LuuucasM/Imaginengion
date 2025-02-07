const std = @import("std");
const assert = std.debug.assert;
const Application = @import("../Core/Application.zig");
const Event = @import("Event.zig").Event;
const EventCategory = @import("EventEnums.zig").EventCategory;
const EventType = @import("EventEnums.zig").EventType;
const Self = @This();

var EventManager: Self = .{};

_InputEventPool: std.ArrayList(Event) = undefined,
_WindowEventPool: std.ArrayList(Event) = undefined,
_Application: *Application = undefined,

var EventGPA = std.heap.GeneralPurposeAllocator(.{}){};

pub fn Init(application: *Application) !void {
    EventManager._InputEventPool = std.ArrayList(Event).init(EventGPA.allocator());
    EventManager._WindowEventPool = std.ArrayList(Event).init(EventGPA.allocator());
    EventManager._Application = application;
}

pub fn Deinit() void {
    EventManager._InputEventPool.deinit();
    EventManager._WindowEventPool.deinit();
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
        EventManager._Application.OnEvent(event);
    }
}

pub fn EventsReset() void {
    _ = EventManager._InputEventPool.clearAndFree();
    _ = EventManager._WindowEventPool.clearAndFree();
}
