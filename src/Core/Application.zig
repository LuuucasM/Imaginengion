const std = @import("std");
const EventManager = @import("../Events/EventManager.zig");
const Event = @import("../Events/Event.zig").Event;
const Window = @import("../Windows/Window.zig");
const Input = @import("../Inputs/Input.zig");
const Program = @import("../Programs/Program.zig");
const AssetManager = @import("../Assets/AssetManager.zig");

const Application: type = @This();

mIsRunning: bool = true,
mIsMinimized: bool = false,
mEngineAllocator: std.mem.Allocator = undefined,
mWindow: Window = undefined,
mProgram: Program = undefined,

pub fn Init(self: *Application, EngineAllocator: std.mem.Allocator) !void {
    try AssetManager.Init(EngineAllocator);
    try Input.Init();
    try EventManager.Init(self);

    self.mWindow = Window.Init();
    self.mProgram = try Program.Init(EngineAllocator, &self.mWindow);
}

pub fn Deinit(self: *Application) !void {
    try self.mProgram.Deinit();
    self.mWindow.Deinit();
    try AssetManager.Deinit();
    EventManager.Deinit();
    Input.Deinit();
}

pub fn Run(self: *Application) !void {
    var timer = try std.time.Timer.start();
    var delta_time: f64 = 0;

    while (self.mIsRunning) : (delta_time = @as(f64, @floatFromInt(timer.lap())) / std.time.ns_per_ms) {
        try self.mProgram.OnUpdate(delta_time);
    }
}

pub fn OnEvent(self: *Application, event: *Event) void {
    const result = switch (event.*) {
        .ET_WindowClose => self.OnWindowClose(),
        .ET_WindowResize => |e| self.OnWindowResize(e._Width, e._Height),
        .ET_KeyPressed => |e| self.mProgram.OnKeyPressedEvent(e),
        else => false,
    };
    _ = result;
}

fn OnWindowClose(self: *Application) bool {
    self.mIsRunning = false;
    return true;
}

fn OnWindowResize(self: *Application, width: usize, height: usize) bool {
    if ((width == 0) and (height == 0)) {
        self.mIsMinimized = true;
    } else {
        self.mIsMinimized = false;
    }

    self.mWindow.OnWindowResize(width, height);
    return false;
}
