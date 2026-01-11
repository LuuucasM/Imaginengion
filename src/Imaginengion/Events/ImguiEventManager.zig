const std = @import("std");
const Program = @import("../Programs/Program.zig");
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const ImguiEventManager = @This();

mEventPool: std.ArrayList(ImguiEvent) = .{},
mProgram: *Program = undefined,

pub fn Init(self: *ImguiEventManager, program: *Program) void {
    self.mProgram = program;
}

pub fn Deinit(self: *ImguiEventManager, engine_allocator: std.mem.Allocator) void {
    self.mEventPool.deinit(engine_allocator);
}

pub fn Insert(self: *ImguiEventManager, engine_allocator: std.mem.Allocator, event: ImguiEvent) !void {
    try self.mEventPool.append(engine_allocator, event);
}

pub fn ProcessEvents(self: *ImguiEventManager, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("ImguiEventManager ProcessEvents", @src());
    defer zone.Deinit();
    const engine_allocator = engine_context.EngineAllocator();
    for (self.mEventPool.items) |*event| {
        try self.mProgram.OnImguiEvent(event, engine_context);
        switch (event.*) {
            .ET_OpenSceneEvent => |e| {
                engine_allocator.free(e.mAbsPath);
            },
            .ET_SaveSceneAsEvent => |e| {
                engine_allocator.free(e.mAbsPath);
            },
            .ET_SaveEntityAsEvent => |e| {
                engine_allocator.free(e.mAbsPath);
            },
            .ET_NewProjectEvent => |e| {
                engine_allocator.free(e.mAbsPath);
            },
            .ET_OpenProjectEvent => |e| {
                engine_allocator.free(e.mAbsPath);
            },
            else => {},
        }
    }
}

pub fn EventsReset(self: *ImguiEventManager, engine_allocator: std.mem.Allocator) void {
    const zone = Tracy.ZoneInit("Imgui Event Reset", @src());
    defer zone.Deinit();
    self.mEventPool.clearAndFree(engine_allocator);
}
