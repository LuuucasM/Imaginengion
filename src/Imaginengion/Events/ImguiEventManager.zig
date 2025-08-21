const std = @import("std");
const Program = @import("../Programs/Program.zig");
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const Tracy = @import("../Core/Tracy.zig");
const Self = @This();

var EventManager: Self = .{};

mEventPool: std.ArrayList(ImguiEvent) = .{},
mProgram: *Program = undefined,

var EventGPA = std.heap.DebugAllocator(.{}).init;
const EventAllocator = EventGPA.allocator();

pub fn Init(program: *Program) !void {
    EventManager.mProgram = program;
}

pub fn Deinit() void {
    EventManager.mEventPool.deinit(EventAllocator);
    _ = EventGPA.deinit();
}

pub fn Insert(event: ImguiEvent) !void {
    try EventManager.mEventPool.append(EventAllocator, event);
}

pub fn ProcessEvents() !void {
    const zone = Tracy.ZoneInit("ImguiEventManager ProcessEvents", @src());
    defer zone.Deinit();
    for (EventManager.mEventPool.items) |*event| {
        try EventManager.mProgram.OnImguiEvent(event);
        switch (event.*) {
            .ET_OpenSceneEvent => |e| {
                EventGPA.allocator().free(e.Path);
            },
            .ET_SaveSceneAsEvent => |e| {
                EventGPA.allocator().free(e.AbsPath);
            },
            .ET_NewProjectEvent => |e| {
                EventGPA.allocator().free(e.Path);
            },
            .ET_OpenProjectEvent => |e| {
                EventGPA.allocator().free(e.Path);
            },
            else => {},
        }
    }
}

pub fn EventsReset() void {
    const zone = Tracy.ZoneInit("Imgui Event Reset", @src());
    defer zone.Deinit();
    EventManager.mEventPool.clearAndFree(EventAllocator);
}

pub fn GetEventAllocator() std.mem.Allocator {
    return EventGPA.allocator();
}
