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

pub fn Init(engine_allocator: std.mem.Allocator, window: *Window, frame_allocator: std.mem.Allocator) !Program {
    return Program{
        ._Impl = try Impl.Init(engine_allocator, window, frame_allocator),
    };
}

pub fn Setup(self: *Program, engine_allocator: std.mem.Allocator) !void {
    try self._Impl.Setup(engine_allocator);
}

pub fn Deinit(self: *Program) !void {
    try self._Impl.Deinit();
}

pub fn OnUpdate(self: *Program, dt: f32) !void {
    try self._Impl.OnUpdate(dt);
}

pub fn OnWindowResize(self: *Program, width: usize, height: usize, frame_allocator: std.mem.Allocator) !bool {
    return try self._Impl.OnWindowResize(width, height, frame_allocator);
}

pub fn OnInputPressedEvent(self: *Program, e: InputPressedEvent, frame_allocator: std.mem.Allocator) !bool {
    return self._Impl.OnInputPressedEvent(e, frame_allocator);
}

pub fn OnImguiEvent(self: *Program, event: *ImguiEvent) !void {
    try self._Impl.OnImguiEvent(event);
}

pub fn OnGameEvent(self: *Program, event: *GameEvent) !void {
    try self._Impl.OnGameEvent(event);
}
