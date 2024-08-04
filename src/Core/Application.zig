const std = @import("std");
const EventManager = @import("../Events/EventManager.zig");
const Event = @import("../Events/Event.zig").Event;
const Window = @import("../Windows/Window.zig");
const Input = @import("../Inputs/Input.zig");
const ThreadPool = @import("../Core/ThreadPool.zig");
const Program = @import("../Programs/Program.zig");

const Application: type = @This();

var ApplicationManager: *Application = undefined;

_IsRunning: bool = true,
_IsMinimized: bool = false,
_EngineAllocator: std.mem.Allocator,
_Window: *Window,
_Program: *Program,

pub fn Init(EngineAllocator: std.mem.Allocator) !void {
    ApplicationManager = try EngineAllocator.create(Application);
    ApplicationManager.* = .{
        ._EngineAllocator = EngineAllocator,
        ._Window = try Window.Init(EngineAllocator),
        ._Program = try Program.Init(EngineAllocator),
    };
    try EventManager.Init(EngineAllocator, OnEvent);
    try Input.Init(EngineAllocator, ApplicationManager._Window.GetNativeWindow());
    try ThreadPool.init(EngineAllocator);
}

pub fn Deinit() void {
    ApplicationManager._Program.Deinit();
    ApplicationManager._Window.Deinit();
    Input.Deinit();
    EventManager.Deinit();
    ThreadPool.deinit();
    ApplicationManager._EngineAllocator.destroy(ApplicationManager);
}

pub fn Run() void {
    while (ApplicationManager._IsRunning) {
        ApplicationManager._Program.OnUpdate();
    }
}

pub fn GetNativeWindow() *void {
    return ApplicationManager._Window.GetNativeWindow();
}

fn OnEvent(event: *Event) void {
    const result = switch (event.*) {
        .ET_WindowClose => OnWindowClose(),
        .ET_WindowResize => |et| OnWindowResize(et._Width, et._Height),
        else => false,
    };
    if (result == false) {
        ApplicationManager._Program.OnEvent(event);
    }
}

fn OnWindowClose() bool {
    ApplicationManager._IsRunning = false;
    return true;
}

fn OnWindowResize(width: usize, height: usize) bool {
    if ((width == 0) and (height == 0)) {
        ApplicationManager._IsMinimized = true;
    } else {
        ApplicationManager._IsMinimized = false;
    }

    ApplicationManager._Window.OnWindowResize(width, height);
    return false;
}
