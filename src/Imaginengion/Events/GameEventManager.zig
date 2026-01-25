const std = @import("std");
const Program = @import("../Programs/Program.zig");
const GameEvent = @import("GameEvent.zig").GameEvent;
const GameEventCategory = @import("GameEvent.zig").GameEventCategory;
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const ClearMode = @import("SystemEventManager.zig").ClearMode;
const GameEventManager = @This();

mEndOfFramePool: std.ArrayList(GameEvent) = .{},
mProgram: *Program = undefined,

pub fn Init(self: *GameEventManager, program: *Program) void {
    self.mProgram = program;
}

pub fn Deinit(self: *GameEventManager, engine_allocator: std.mem.Allocator) void {
    self.mEndOfFramePool.deinit(engine_allocator);
}

pub fn Insert(self: *GameEventManager, engine_allocator: std.mem.Allocator, event: GameEvent) !void {
    const zone = Tracy.ZoneInit("Game Insert Events", @src());
    defer zone.Deinit();
    switch (event.GetEventCategory()) {
        .EC_EndOfFrame => try self.mEndOfFramePool.append(engine_allocator, event),
        else => @panic("Default Events are not allowed!\n"),
    }
}

pub fn ProcessEvents(self: *GameEventManager, engine_context: *EngineContext, eventCategory: GameEventCategory) !void {
    const zone = Tracy.ZoneInit("Game ProcessEvents", @src());
    defer zone.Deinit();
    const array = switch (eventCategory) {
        .EC_EndOfFrame => self.mEndOfFramePool,
        else => @panic("Default Events are not allowed!\n"),
    };

    for (array.items) |*event| {
        try self.mProgram.OnGameEvent(engine_context, event);
    }
}

pub fn EventsReset(self: *GameEventManager, engine_allocator: std.mem.Allocator, clear_mode: ClearMode) void {
    const zone = Tracy.ZoneInit("Game Event Reset", @src());
    defer zone.Deinit();

    switch (clear_mode) {
        .ClearAndFree => {
            _ = self.mEndOfFramePool.clearAndFree(engine_allocator);
        },
        .ClearRetainingCapacity => {
            _ = self.mEndOfFramePool.clearRetainingCapacity();
        },
    }
}
