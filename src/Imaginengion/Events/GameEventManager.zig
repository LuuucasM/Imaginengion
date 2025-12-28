const std = @import("std");
const assert = std.debug.assert;
const Program = @import("../Programs/Program.zig");
const GameEvent = @import("GameEvent.zig").GameEvent;
const GameEventCategory = @import("GameEvent.zig").GameEventCategory;
const Tracy = @import("../Core/Tracy.zig");
const GameEventManager = @This();

mEndOfFramePool: std.ArrayList(GameEvent) = .{},
mProgram: *Program = undefined,

pub fn Init(self: *GameEventManager, program: *Program) !void {
    self.mProgram = program;
}

pub fn Deinit(self: *GameEventManager, engine_allocator: std.mem.Allocator) void {
    self.mEndOfFramePool.deinit(engine_allocator);
}

pub fn Insert(self: *GameEventManager, event: GameEvent, engine_allocator: std.mem.Allocator) !void {
    const zone = Tracy.ZoneInit("Game Insert Events", @src());
    defer zone.Deinit();
    switch (event.GetEventCategory()) {
        .EC_EndOfFrame => try self.mEndOfFramePool.append(engine_allocator, event),
        else => @panic("Default Events are not allowed!\n"),
    }
}

pub fn ProcessEvents(self: *GameEventManager, eventCategory: GameEventCategory) !void {
    const zone = Tracy.ZoneInit("Game ProcessEvents", @src());
    defer zone.Deinit();
    const array = switch (eventCategory) {
        .EC_EndOfFrame => self.mEndOfFramePool,
        else => @panic("Default Events are not allowed!\n"),
    };

    for (array.items) |*event| {
        try self.mProgram.OnGameEvent(event);
    }
}

pub fn EventsReset(self: *GameEventManager, engine_allocator: std.mem.Allocator) void {
    const zone = Tracy.ZoneInit("Game Event Reset", @src());
    defer zone.Deinit();
    _ = self.mEndOfFramePool.clearAndFree(engine_allocator);
}
