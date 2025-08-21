const std = @import("std");
const assert = std.debug.assert;
const Program = @import("../Programs/Program.zig");
const GameEvent = @import("GameEvent.zig").GameEvent;
const GameEventCategory = @import("GameEvent.zig").GameEventCategory;
const Tracy = @import("../Core/Tracy.zig");
const Self = @This();

var EventManager: Self = .{};

mPreRenderEventPool: std.ArrayList(GameEvent) = .{},
mProgram: *Program = undefined,

var EventGPA = std.heap.DebugAllocator(.{}).init;
const EventAllocator = EventGPA.allocator();

pub fn Init(program: *Program) !void {
    EventManager.mProgram = program;
}

pub fn Deinit() void {
    EventManager.mPreRenderEventPool.deinit(EventAllocator);
    _ = EventGPA.deinit();
}

pub fn Insert(event: GameEvent) !void {
    switch (event.GetEventCategory()) {
        .EC_PreRender => try EventManager.mPreRenderEventPool.append(EventAllocator, event),
        else => @panic("Default Events are not allowed!\n"),
    }
}

pub fn ProcessEvents(eventCategory: GameEventCategory) !void {
    const zone = Tracy.ZoneInit("Game ProcessEvents", @src());
    defer zone.Deinit();
    const array = switch (eventCategory) {
        .EC_PreRender => EventManager.mPreRenderEventPool,
        else => @panic("Default Events are not allowed!\n"),
    };

    for (array.items) |*event| {
        try EventManager.mProgram.OnGameEvent(event);
    }
}

pub fn EventsReset() void {
    const zone = Tracy.ZoneInit("Game Event Reset", @src());
    defer zone.Deinit();
    _ = EventManager.mPreRenderEventPool.clearAndFree(EventAllocator);
}
