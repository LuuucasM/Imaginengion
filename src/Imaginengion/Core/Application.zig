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
const Window = @import("../Windows/Window.zig");
const Program = @import("../Programs/Program.zig");
const EngineContext = @import("EngineContext.zig");
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
    try self.mEngineContext.Init();
    try self.mProgram.Init(&self.mWindow, &self.mEngineContext);
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

        _ = self.mEngineContext._internal.FrameArena.reset(.free_all);
        self.mEngineContext.mEngineStats.ResetStats();
    }
}
