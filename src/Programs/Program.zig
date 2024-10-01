const std = @import("std");
const Event = @import("../Events/Event.zig").Event;
const Program = @This();

const Impl = @import("EditorProgram.zig");
_Impl: Impl = .{},

pub fn Init(self: *Program, EngineAllocator: std.mem.Allocator) !void {
    try self._Impl.Init(EngineAllocator);
}

pub fn Deinit(self: *Program) void {
    self._Impl.Deinit();
}

pub fn OnUpdate(self: *Program, dt: f64) !void {
    try self._Impl.OnUpdate(dt);
}

pub fn OnEvent(self: Program, event: *Event) void {
    self._Impl.OnEvent(event);
}
