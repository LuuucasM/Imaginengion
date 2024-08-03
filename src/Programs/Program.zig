const std = @import("std");
const Event = @import("../Events/Event.zig").Event;
const Impl = @import("EditorProgram.zig");
const Program = @This();

_Impl: Impl,
_EngineAllocator: std.mem.Allocator,

pub fn Init(EngineAllocator: std.mem.Allocator) !*Program {
    const ptr = try EngineAllocator.create(Program);
    ptr.* = .{
        ._Impl = .{},
        ._EngineAllocator = EngineAllocator,
    };
    ptr._Impl.Init();
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
