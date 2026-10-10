const std = @import("std");
const Window = @import("../Windows/Window.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const EventResult = @import("../Events/EventManager.zig").EventResult;
const Program = @This();

/// The program the engine runs, picked by the executable: its root file declares `pub const Program`, the editor's
/// EditorProgram (src/Editor.zig) or a game's GameProgram (src/Game.zig)
const Impl = @import("root").Program;
_Impl: Impl = .{},

/// `args` are the executable's command line arguments
pub fn Init(self: *Program, engine_context: *EngineContext, args: std.process.Args) !void {
    try self._Impl.Init(engine_context, args);
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
