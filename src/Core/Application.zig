const std = @import("std");

const EventManager = @import("../Events/EventManager.zig");
const Event = @import("../Events/Event.zig");
const Window = @import("../Windows/Window.zig");
const Input = @import("../Inputs/Input.zig");

const Application: type = @This();

_IsRunning: bool = true,
_IsMinimized: bool = false,
_EngineAllocator: std.mem.Allocator,
_Window: *Window,
//TODO: _Program: *Program,

pub fn Init(EngineAllocator: std.mem.Allocator) !*Application {
    const app = try EngineAllocator.create(Application);
    app.* = .{
        ._EngineAllocator = EngineAllocator,
        ._Window = try Window.Init(EngineAllocator),
    };
    try EventManager.Init(EngineAllocator);
    try Input.Init(EngineAllocator, app._Window.GetNativeWindow());
    return app;
}

pub fn Deinit(self: *Application) void {
    self._Window.Deinit();
    EventManager.Deinit();
    self._EngineAllocator.destroy(self);
}

pub fn Run(self: Application) void {
    while (self._IsRunning) {
        EventManager.ProcessInputEvents(OnEvent);
    }
    //TODO: Prograom.OnUpdate()
}

fn OnEvent(event: Event) void {
    switch (event.GetEventName()) {
        .EN_KeyPressed => std.debug.print("A KEY PRESS !", .{}),
        .EN_KeyReleased => std.debug.print("KEY RELEASE EVENT !", .{}),
        else => @panic("This event isnt implemented yet !"),
    }
}

fn OnWindowClose() bool {
    return true;
}

fn OnWindowResize(width: usize, height: usize) bool {
    _ = width;
    _ = height;
    return false;
}
