const std = @import("std");
const SystemEvent = @import("../Events/SystemEvent.zig").SystemEvent;
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const GameEvent = @import("../Events/GameEvent.zig").GameEvent;
const InputPressedEvent = @import("../Events/SystemEvent.zig").InputPressedEvent;
const WindowResizeEvent = @import("../Events/SystemEvent.zig").WindowResizeEvent;
const Window = @import("../Windows/Window.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Program = @This();

const Impl = @import("EditorProgram.zig");
_Impl: Impl = .{},

pub fn Init(self: *Program, window: *Window, engine_context: *EngineContext) !void {
    try self._Impl.Init(window, engine_context);
}

pub fn Deinit(self: *Program, engine_context: *EngineContext) !void {
    try self._Impl.Deinit(engine_context);
}

pub fn OnUpdate(self: *Program, dt: f32, engine_context: *EngineContext) !void {
    try self._Impl.OnUpdate(dt, engine_context);
}

pub fn OnWindowResize(self: *Program, width: usize, height: usize) !bool {
    return try self._Impl.OnWindowResize(width, height);
}

pub fn OnInputPressedEvent(self: *Program, engine_context: *EngineContext, e: InputPressedEvent) !bool {
    return self._Impl.OnInputPressedEvent(engine_context, e);
}

pub fn OnImguiEvent(self: *Program, event: *ImguiEvent, engine_context: *EngineContext) !void {
    try self._Impl.OnImguiEvent(event, engine_context);
}

pub fn OnGameEvent(self: *Program, engine_context: *EngineContext, event: *GameEvent) !void {
    try self._Impl.OnGameEvent(engine_context, event);
}
