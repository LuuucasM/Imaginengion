const std = @import("std");
const EventManager = @import("../Events/EventManager.zig");
const Event = @import("../Events/Event.zig").Event;
const Window = @import("../Windows/Window.zig");
const Input = @import("../Inputs/Input.zig");

const Application: type = @This();

var APPLICATION: *Application = undefined;

_IsRunning: bool = true,
_IsMinimized: bool = false,
_EngineAllocator: std.mem.Allocator,
_Window: *Window,
//TODO: _Program: *Program,

pub fn Init(EngineAllocator: std.mem.Allocator) !void {
    APPLICATION = try EngineAllocator.create(Application);
    APPLICATION.* = .{
        ._EngineAllocator = EngineAllocator,
        ._Window = try Window.Init(EngineAllocator),
    };
    try EventManager.Init(EngineAllocator, OnEvent);
    try Input.Init(EngineAllocator, APPLICATION._Window.GetNativeWindow());
}

pub fn Deinit() void {
    APPLICATION._Window.Deinit();
    EventManager.Deinit();
    APPLICATION._EngineAllocator.destroy(APPLICATION);
}

pub fn Run() void {
    while (APPLICATION._IsRunning) {
        Input.PollInputEvents();
        EventManager.ProcessEvents(.EC_Input);
        EventManager.ProcessEvents(.EC_Window);
        EventManager.EventsReset();
    }
    //TODO: Prograom.OnUpdate()
}

fn OnEvent(event: *Event) void {
    const result = switch (event.*) {
        .ET_WindowClose => OnWindowClose(),
        .ET_WindowResize => |et| OnWindowResize(et._Width, et._Height),
        else => false,
    };
    _ = result;
}

fn OnWindowClose() bool {
    APPLICATION._IsRunning = false;
    return true;
}

fn OnWindowResize(width: usize, height: usize) bool {
    if ((width == 0) and (height == 0)) {
        APPLICATION._IsMinimized = true;
    } else {
        APPLICATION._IsMinimized = false;
    }

    APPLICATION._Window.OnWindowResize(width, height);
    return false;
}
