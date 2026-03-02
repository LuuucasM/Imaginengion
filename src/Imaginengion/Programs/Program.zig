const std = @import("std");
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

pub fn OnUpdate(self: *Program, engine_context: *EngineContext) !void {
    try self._Impl.OnUpdate(engine_context);
}
