const std = @import("std");
const Event = @import("../Events/Event.zig").Event;
const Renderer = @import("../Renderer/Renderer.zig");
const Program = @This();

const Impl = @import("EditorProgram.zig");
_Impl: Impl,

pub fn Init(EngineAllocator: std.mem.Allocator) !Program {
    try Renderer.Init(EngineAllocator);
    return Program{
        ._Impl = try Impl.Init(EngineAllocator),
    };
}

pub fn Deinit(self: *Program) !void {
    try self._Impl.Deinit();
    Renderer.Deinit();
}

pub fn OnUpdate(self: *Program, dt: f64) !void {
    try self._Impl.OnUpdate(dt);
}

pub fn OnEvent(self: Program, event: *Event) void {
    self._Impl.OnEvent(event);
}
