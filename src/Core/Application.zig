const std = @import("std");
const EventManager = @import("../Events/EventManager.zig");
const Event = @import("../Events/Event.zig").Event;
const Window = @import("../Windows/Window.zig");
const Input = @import("../Inputs/Input.zig");
const Program = @import("../Programs/Program.zig");
const ThreadPool = @import("ThreadPool.zig");
const AssetManager = @import("../Assets/AssetManager.zig");

const Application: type = @This();

var ApplicationManager: *Application = undefined;

_IsRunning: bool = true,
_IsMinimized: bool = false,
_EngineAllocator: std.mem.Allocator,
_Window: Window = .{},
_Program: Program = .{},

pub fn Init(EngineAllocator: std.mem.Allocator) !void {
    ApplicationManager = try EngineAllocator.create(Application);
    ApplicationManager.* = .{
        ._EngineAllocator = EngineAllocator,
    };
    ApplicationManager._Window.Init();
    try ApplicationManager._Program.Init(EngineAllocator);
    ApplicationManager._Window.SetVSync(true);
    try EventManager.Init(EngineAllocator, OnEvent);
    try Input.Init(EngineAllocator, ApplicationManager._Window.GetNativeWindow());
    try ThreadPool.init(EngineAllocator);
    try AssetManager.Init(EngineAllocator);
}

pub fn Deinit() void {
    ApplicationManager._Program.Deinit();
    ApplicationManager._Window.Deinit();
    Input.Deinit();
    EventManager.Deinit();
    ThreadPool.deinit();
    AssetManager.Deinit();
    ApplicationManager._EngineAllocator.destroy(ApplicationManager);
}

pub fn Run() !void {
    var timer = try std.time.Timer.start();
    var delta_time: f64 = 0;

    while (ApplicationManager._IsRunning) : (delta_time = @as(f64, @floatFromInt(timer.lap())) / std.time.ns_per_ms) {
        try ApplicationManager._Program.OnUpdate(delta_time);
    }
}

pub fn GetNativeWindow() *anyopaque {
    return ApplicationManager._Window.GetNativeWindow();
}

pub fn OnEvent(event: *Event) void {
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
