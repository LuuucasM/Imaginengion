const std = @import("std");
const Window = @import("../Windows/Window.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const EventResult = @import("../Events/EventManager.zig").EventResult;
const Program = @This();

const Impl = @import("EditorProgram.zig");
_Impl: Impl = .{},

pub fn Init(self: *Program, engine_context: *EngineContext) !void {
    try self._Impl.Init(engine_context);
}

pub fn Deinit(self: *Program, engine_context: *EngineContext) void {
    self._Impl.Deinit(engine_context);
}

pub fn OnUpdate(self: *Program, engine_context: *EngineContext) !void {
    try self._Impl.OnUpdate(engine_context);
}

/// The single synchronous entry point for every event type in the engine. Every event manager's
/// mSyncCallback points here; see EngineContext.SetSyncCallbacks.
pub fn OnEvent(self: *Program, engine_context: *EngineContext, event: anytype) anyerror!EventResult {
    return self._Impl.OnEvent(engine_context, event);
}
