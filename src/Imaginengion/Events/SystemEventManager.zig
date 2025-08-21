const std = @import("std");
const assert = std.debug.assert;
const Application = @import("../Core/Application.zig");
const SystemEvent = @import("SystemEvent.zig").SystemEvent;
const SystemEventCategory = @import("SystemEvent.zig").SystemEventCategory;
const Tracy = @import("../Core/Tracy.zig");
const Self = @This();

var EventManager: Self = .{};

_InputEventPool: std.ArrayList(SystemEvent) = .{},
_WindowEventPool: std.ArrayList(SystemEvent) = .{},
_Application: *Application = undefined,

var EventGPA = std.heap.DebugAllocator(.{}).init;
const EventAllocator = EventGPA.allocator();

pub fn Init(application: *Application) !void {
    EventManager._Application = application;
}

pub fn Deinit() void {
    EventManager._InputEventPool.deinit(EventAllocator);
    EventManager._WindowEventPool.deinit(EventAllocator);
    _ = EventGPA.deinit();
}

pub fn Insert(event: SystemEvent) !void {
    switch (event.GetEventCategory()) {
        .EC_Input => try EventManager._InputEventPool.append(EventAllocator, event),
        .EC_Window => try EventManager._WindowEventPool.append(EventAllocator, event),
        else => @panic("Default Events are not allowed!\n"),
    }
}

pub fn ProcessEvents(eventCategory: SystemEventCategory) !void {
    const zone = Tracy.ZoneInit("ProcessEvents", @src());
    defer zone.Deinit();
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
    const zone = Tracy.ZoneInit("System Event Reset", @src());
    defer zone.Deinit();
    _ = EventManager._InputEventPool.clearAndFree(EventAllocator);
    _ = EventManager._WindowEventPool.clearAndFree(EventAllocator);
}
