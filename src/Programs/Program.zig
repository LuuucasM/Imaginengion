const std = @import("std");
const Event = @import("../Events/Event.zig").Event;
const InputEvents = @import("../Events/InputEvents.zig");
const Renderer = @import("../Renderer/Renderer.zig");
const Window = @import("../Windows/Window.zig");
const Program = @This();

const Impl = @import("EditorProgram.zig");
_Impl: Impl,

pub fn Init(EngineAllocator: std.mem.Allocator, window: *Window) !Program {
    try Renderer.Init(EngineAllocator, window);
    return Program{
        ._Impl = try Impl.Init(EngineAllocator, window),
    };
}

pub fn Deinit(self: *Program) !void {
    try self._Impl.Deinit();
    Renderer.Deinit();
}

pub fn OnUpdate(self: *Program, dt: f64) !void {
    try self._Impl.OnUpdate(dt);
}

pub fn OnKeyPressedEvent(self: *Program, e: InputEvents.KeyPressedEvent) bool {
    return self._Impl.OnKeyPressedEvent(e);
}
