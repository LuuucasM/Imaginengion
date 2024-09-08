const std = @import("std");
const Event = @import("../Events/Event.zig").Event;
const Program = @This();

const Impl = @import("EditorProgram.zig");
_Impl: Impl,

_EngineAllocator: std.mem.Allocator,

pub fn Init(EngineAllocator: std.mem.Allocator) !*Program {
    const ptr = try EngineAllocator.create(Program);
    ptr.* = .{
        ._Impl = .{},
        ._EngineAllocator = EngineAllocator,
    };
    try ptr._Impl.Init(EngineAllocator);
    return ptr;
}

pub fn Deinit(self: *Program) void {
    self._Impl.Deinit();
    self._EngineAllocator.destroy(self);
}

pub fn OnUpdate(self: *Program, dt: f64) !void {
    try self._Impl.OnUpdate(dt);
}

pub fn OnInputEvent(self: Program, event: *Event) void {
    self._Impl.OnInputEvent(event);
}

pub fn OnWindowEvent(self: Program, event: *Event) void {
    self._Impl.OnWindowEvent(event);
}
