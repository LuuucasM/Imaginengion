const std = @import("std");
const assert = std.debug.assert;
const Application = @import("../Core/Application.zig");
const SystemEvent = @import("SystemEvent.zig").SystemEvent;
const SystemEventCategory = @import("SystemEvent.zig").SystemEventCategory;
const Tracy = @import("../Core/Tracy.zig");
const SystemEventManager = @This();

_InputEventPool: std.ArrayList(SystemEvent) = .{},
_WindowEventPool: std.ArrayList(SystemEvent) = .{},
_Application: *Application = undefined,

pub fn Init(self: *SystemEventManager, application: *Application) !void {
    self._Application = application;
}

pub fn Deinit(self: *SystemEventManager, engine_allocator: std.mem.Allocator) void {
    self._InputEventPool.deinit(engine_allocator);
    self._WindowEventPool.deinit(engine_allocator);
}

pub fn Insert(self: *SystemEventManager, event: SystemEvent, engine_allocator: std.mem.Allocator) !void {
    switch (event.GetEventCategory()) {
        .EC_Input => try self._InputEventPool.append(engine_allocator, event),
        .EC_Window => try self._WindowEventPool.append(engine_allocator, event),
        else => @panic("Default Events are not allowed!\n"),
    }
}

pub fn ProcessEvents(self: *SystemEventManager, eventCategory: SystemEventCategory) !void {
    const zone = Tracy.ZoneInit("ProcessEvents", @src());
    defer zone.Deinit();
    const array = switch (eventCategory) {
        .EC_Input => self._InputEventPool,
        .EC_Window => self._WindowEventPool,
        else => @panic("Default Events are not allowed!\n"),
    };

    for (array.items) |*event| {
        try self._Application.OnEvent(event);
    }
}

pub fn EventsReset(self: *SystemEventManager, engine_allocator: std.mem.Allocator) void {
    const zone = Tracy.ZoneInit("System Event Reset", @src());
    defer zone.Deinit();
    _ = self._InputEventPool.clearAndFree(engine_allocator);
    _ = self._WindowEventPool.clearAndFree(engine_allocator);
}
