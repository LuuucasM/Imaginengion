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

pub fn OnUpdate(self: Program) void {
    self._Impl.OnUpdate();
}

pub fn OnEvent(self: Program, event: *Event) void {
    self._Impl.OnEvent(event);
}
