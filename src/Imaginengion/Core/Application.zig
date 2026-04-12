//! Defines the central `Application` struct, which acts as the entry point for the engine.
//!
//! This module is responsible for initializing and managing all core engine systems,
//! including windowing, input, asset management, event routing, and the engine context.
//!
//! It encapsulates both the runtime and editor modes of the engine, coordinating setup and teardown,
//! and it provides the main execution loop that drives updates, event polling, and rendering.
//!
//! Typical usage involves constructing an `Application`, calling `Init`, and running the main loop
//! via the appropriate `Run` method for the editor or game.

const std = @import("std");
const builtin = @import("builtin");
const Window = @import("../Windows/Window.zig");
const Program = @import("../Programs/Program.zig");
const EngineContext = @import("EngineContext.zig");
const sdl = @import("CImports.zig").sdl;
const Tracy = @import("Tracy.zig");

const Application: type = @This();

mProgram: Program = .{},
mEngineContext: EngineContext = .{},

/// Initializes the engine application.
///
/// Parameters:
/// - `self`: A pointer to the `Application` instance to initialize.
/// - `engine_allocator`: Allocator used for setting up subsystems.
///
/// Returns:
/// - `!void` on failure to initialize any core system returns the error else returns nothing.
pub fn Init(self: *Application) !void {
    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) != 0) {
        return error.SDLInitFail;
    }
    if (builtin.mode == .Debug) {
        sdl.SDL_SetLogOutputFunction(SDLLogCallback, null);
        sdl.SDL_SetLogPriority(sdl.SDL_LOG_CATEGORY_GPU, sdl.SDL_LOG_PRIORITY_VERBOSE);
    }
    try self.mEngineContext.Init();
    try self.mProgram.Init(&self.mEngineContext);
}

/// Shuts down the application and cleans up resources.
///
/// Parameters:
/// - `self`: A pointer to the `Application` instance.
///
/// Returns:
/// - `!void` on deinitialization error return the error else return nothing.
pub fn Deinit(self: *Application) !void {
    const zone = Tracy.ZoneInit("Application::Deinit", @src());
    defer zone.Deinit();
    try self.mProgram.Deinit(&self.mEngineContext);
    try self.mEngineContext.DeInit();
    sdl.SDL_Quit();
}

/// Starts the main loop of the engine.
///
/// Parameters:
/// - `self`: A pointer to the `Application` instance.
///
/// Returns:
/// - `!void` if an update loop iteration fails return the error else return nothing.
pub fn Run(self: *Application) !void {
    var frame_timer = try std.time.Timer.start();

    while (self.mEngineContext.mIsRunning) : (self.mEngineContext.mDT = @as(f32, @floatFromInt(frame_timer.lap())) / std.time.ns_per_s) {
        defer Tracy.FrameMark();

        const zone = Tracy.ZoneInit("Main Loop", @src());
        defer zone.Deinit();

        try self.mProgram.OnUpdate(&self.mEngineContext);

        _ = self.mEngineContext._Internal.FrameArena.reset(.free_all);
        self.mEngineContext.mEngineStats.ResetStats();
    }
}

fn SDLLogCallback(_: ?*anyopaque, category: c_int, priority: sdl.SDL_LogPriority, message: [*c]const u8) callconv(.c) void {
    const category_str = switch (category) {
        sdl.SDL_LOG_CATEGORY_GPU => "GPU",
        sdl.SDL_LOG_CATEGORY_APPLICATION => "APPLICATION",
        sdl.SDL_LOG_CATEGORY_ERROR => "ERROR",
        sdl.SDL_LOG_CATEGORY_RENDER => "RENDER",
        else => "OTHER",
    };

    switch (priority) {
        sdl.SDL_LOG_PRIORITY_INFO => std.log.info("[SDL/{s}] {s}", .{ category_str, message }),
        sdl.SDL_LOG_PRIORITY_WARN => std.log.warn("[SDL/{s}] {s}", .{ category_str, message }),
        sdl.SDL_LOG_PRIORITY_ERROR => std.log.err("[SDL/{s}] {s}", .{ category_str, message }),
        sdl.SDL_LOG_PRIORITY_CRITICAL => std.log.err("[SDL/{s}] {s}", .{ category_str, message }),
        else => std.log.debug("[SDL/{s}] {s}", .{ category_str, message }),
    }
}
