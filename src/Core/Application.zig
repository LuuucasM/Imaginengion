const std = @import("std");
const EventManager = @import("../Events/EventManager.zig");
const Event = @import("../Events/Event.zig").Event;
const Window = @import("../Windows/Window.zig");
const Input = @import("../Inputs/Input.zig");
const ThreadPool = @import("../Core/ThreadPool.zig");
const Program = @import("../Programs/Program.zig");
const tracy = @import("CImports.zig").tracy;

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
    var timer = std.time.Timer.start() catch |err| {
        std.log.err("{}\n", .{err});
        @panic("Could not start timer in Application::Run\n");
    };
    var delta_time: f64 = 0;

    while (ApplicationManager._IsRunning) : (delta_time = @as(f64, @floatFromInt(timer.lap())) / std.time.ns_per_ms) {
        ApplicationManager._Program.OnUpdate(delta_time);
    }
}

pub fn GetNativeWindow() *void {
    return ApplicationManager._Window.GetNativeWindow();
}

fn OnEvent(event: *Event) void {
    const result = switch (event.*) {
        .ET_WindowClose => OnWindowClose(),
        .ET_WindowResize => |e| OnWindowResize(e._Width, e._Height),
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
