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
const EventManager = @import("../Events/SystemEventManager.zig");
const SystemEvent = @import("../Events/SystemEvent.zig").SystemEvent;
const Window = @import("../Windows/Window.zig");
const Input = @import("../Inputs/Input.zig");
const Program = @import("../Programs/Program.zig");
const AssetManager = @import("../Assets/AssetManager.zig");
const ImguiEventManager = @import("../Events/ImguiEventManager.zig");
const GameEventManager = @import("../Events/GameEventManager.zig");
const StaticEngineContext = @import("EngineContext.zig");

const Application: type = @This();

mIsRunning: bool = true,
mIsMinimized: bool = false,
mWindow: Window = undefined,
mProgram: Program = undefined,

/// Initializes the engine application.
///
/// Parameters:
/// - `self`: A pointer to the `Application` instance to initialize.
/// - `engine_allocator`: Allocator used for setting up subsystems.
///
/// Returns:
/// - `!void` on failure to initialize any core system returns the error else returns nothing.
pub fn Init(self: *Application, engine_allocator: std.mem.Allocator) !void {
    try AssetManager.Init();
    try Input.Init();
    try EventManager.Init(self);

    self.mWindow = Window.Init();
    self.mProgram = try Program.Init(engine_allocator, &self.mWindow);
    try self.mProgram.Setup();
    try ImguiEventManager.Init(&self.mProgram);
    try GameEventManager.Init(&self.mProgram);
    self.mWindow.SetVSync(false);

    StaticEngineContext.Init();
}

/// Shuts down the application and cleans up resources.
///
/// Parameters:
/// - `self`: A pointer to the `Application` instance.
///
/// Returns:
/// - `!void` on deinitialization error return the error else return nothing.
pub fn Deinit(self: *Application) !void {
    try self.mProgram.Deinit();
    self.mWindow.Deinit();
    try AssetManager.Deinit();
    EventManager.Deinit();
    Input.Deinit();
}

/// Starts the main loop of the engine.
///
/// Parameters:
/// - `self`: A pointer to the `Application` instance.
///
/// Returns:
/// - `!void` if an update loop iteration fails return the error else return nothing.
pub fn Run(self: *Application) !void {
    var timer = try std.time.Timer.start();
    var delta_time: f32 = 0;

    while (self.mIsRunning) : (delta_time = @as(f32, @floatFromInt(timer.lap())) / std.time.ns_per_s) {
        StaticEngineContext.SetDT(delta_time);
        try self.mProgram.OnUpdate(delta_time);
    }
}

/// Propagates system-level events such as window and input events.
///
/// Parameters:
/// - `self`: A pointer to the `Application`.
/// - `event`: A pointer to the `SystemEvent` to process.
///
/// Returns:
/// - `!void` if event propagation fails return the error else return nothing.
pub fn OnEvent(self: *Application, event: *SystemEvent) !void {
    var cont_bool = true;

    cont_bool = cont_bool and switch (event.*) {
        .ET_WindowClose => self.OnWindowClose(),
        .ET_WindowResize => |e| try self.OnWindowResize(e._Width, e._Height),
        .ET_InputPressed => |e| try self.mProgram.OnInputPressedEvent(e),
        else => true,
    };
}

/// Handles the window close event.
///
/// Parameters:
/// - `self`: The application instance.
///
/// Returns:
/// - `false` to stop further propagation of the event.
fn OnWindowClose(self: *Application) bool {
    self.mIsRunning = false;
    return false;
}

/// Handles window resize events.
///
/// Parameters:
/// - `self`: The application instance.
/// - `width`: The new width of the window.
/// - `height`: The new height of the window.
///
/// Returns:
/// - `true` to continue event propagation.
fn OnWindowResize(self: *Application, width: usize, height: usize) !bool {
    if ((width == 0) or (height == 0)) {
        self.mIsMinimized = true;
    } else {
        self.mIsMinimized = false;
    }

    self.mWindow.OnWindowResize(width, height);
    _ = try self.mProgram.OnWindowResize(width, height);
    return true;
}
