const std = @import("std");
const SystemEvent = @import("../Events/SystemEvent.zig").SystemEvent;
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const GameEvent = @import("../Events/GameEvent.zig").GameEvent;
const KeyPressedEvent = @import("../Events/SystemEvent.zig").KeyPressedEvent;
const Renderer = @import("../Renderer/Renderer.zig");
const Window = @import("../Windows/Window.zig");
const Program = @This();

const Impl = @import("EditorProgram.zig");
_Impl: Impl,

pub fn Init(window: *Window) !Program {
    try Renderer.Init(window);
    return Program{
        ._Impl = try Impl.Init(window),
    };
}

pub fn Deinit(self: *Program) !void {
    try self._Impl.Deinit();
    Renderer.Deinit();
}

pub fn OnUpdate(self: *Program, dt: f64) !void {
    try self._Impl.OnUpdate(dt);
}

pub fn OnKeyPressedEvent(self: *Program, e: KeyPressedEvent) bool {
    return self._Impl.OnKeyPressedEvent(e);
}

pub fn OnImguiEvent(self: *Program, event: *ImguiEvent) !void {
    try self._Impl.OnImguiEvent(event);
}

pub fn OnGameEvent(self: *Program, event: *GameEvent) !void {
    try self._Impl.OnGameEvent(event);
}
