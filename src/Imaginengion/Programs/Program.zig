const std = @import("std");
const SystemEvent = @import("../Events/SystemEvent.zig").SystemEvent;
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const GameEvent = @import("../Events/GameEvent.zig").GameEvent;
const InputPressedEvent = @import("../Events/SystemEvent.zig").InputPressedEvent;
const WindowResizeEvent = @import("../Events/SystemEvent.zig").WindowResizeEvent;
const Window = @import("../Windows/Window.zig");
const Program = @This();

const Impl = @import("EditorProgram.zig");
_Impl: Impl,

pub fn Init(engine_allocator: std.mem.Allocator, window: *Window) !Program {
    return Program{
        ._Impl = try Impl.Init(engine_allocator, window),
    };
}

pub fn Setup(self: *Program) !void {
    try self._Impl.Setup();
}

pub fn Deinit(self: *Program) !void {
    try self._Impl.Deinit();
}

pub fn OnUpdate(self: *Program, dt: f32) !void {
    try self._Impl.OnUpdate(dt);
}

pub fn OnWindowResize(self: *Program, width: usize, height: usize) !bool {
    return try self._Impl.OnWindowResize(width, height);
}

pub fn OnInputPressedEvent(self: *Program, e: InputPressedEvent) !bool {
    return self._Impl.OnInputPressedEvent(e);
}

pub fn OnImguiEvent(self: *Program, event: *ImguiEvent) !void {
    try self._Impl.OnImguiEvent(event);
}

pub fn OnGameEvent(self: *Program, event: *GameEvent) !void {
    try self._Impl.OnGameEvent(event);
}
