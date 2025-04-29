const std = @import("std");
const assert = std.debug.assert;
const Application = @import("../Core/Application.zig");
const SystemEvent = @import("SystemEvent.zig").SystemEvent;
const SystemEventCategory = @import("SystemEvent.zig").SystemEventCategory;
const Self = @This();

var EventManager: Self = .{};

_InputEventPool: std.ArrayList(SystemEvent) = undefined,
_WindowEventPool: std.ArrayList(SystemEvent) = undefined,
_Application: *Application = undefined,

var EventGPA = std.heap.DebugAllocator(.{}).init;

pub fn Init(application: *Application) !void {
    EventManager._InputEventPool = std.ArrayList(SystemEvent).init(EventGPA.allocator());
    EventManager._WindowEventPool = std.ArrayList(SystemEvent).init(EventGPA.allocator());
    EventManager._Application = application;
}

pub fn Deinit() void {
    EventManager._InputEventPool.deinit();
    EventManager._WindowEventPool.deinit();
    _ = EventGPA.deinit();
}

pub fn Insert(event: SystemEvent) !void {
    switch (event.GetEventCategory()) {
        .EC_Input => try EventManager._InputEventPool.append(event),
        .EC_Window => try EventManager._WindowEventPool.append(event),
        else => @panic("Default Events are not allowed!\n"),
    }
}

pub fn ProcessEvents(eventCategory: SystemEventCategory) !void {
    const array = switch (eventCategory) {
        .EC_Input => EventManager._InputEventPool,
        .EC_Window => EventManager._WindowEventPool,
        else => @panic("Default Events are not allowed!\n"),
    };

    for (array.items) |*event| {
        try EventManager._Application.OnEvent(event);
    }
}

pub fn EventsReset() void {
    _ = EventManager._InputEventPool.clearAndFree();
    _ = EventManager._WindowEventPool.clearAndFree();
}
