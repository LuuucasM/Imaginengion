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
const SystemEvent = @import("../Events/SystemEvent.zig").SystemEvent;
const Window = @import("../Windows/Window.zig");
const Input = @import("../Inputs/Input.zig");
const Program = @import("../Programs/Program.zig");
const AudioManager = @import("../AudioManager/AudioManager.zig");
const AssetManager = @import("../Assets/AssetManager.zig");
const SystemEventManager = @import("../Events/SystemEventManager.zig");
const ImguiEventManager = @import("../Events/ImguiEventManager.zig");
const GameEventManager = @import("../Events/GameEventManager.zig");
const EngineContext = @import("EngineContext.zig");
const Tracy = @import("Tracy.zig");

const Application: type = @This();

mIsRunning: bool = true,
mIsMinimized: bool = false,

mWindow: Window = .{},
mProgram: Program = .{},
mEngineContext: EngineContext = .{},

mEngineGPA: std.heap.DebugAllocator(.{}) = std.heap.DebugAllocator(.{}).init,
mEngineAllocator: std.mem.Allocator = undefined,
mFrameArena: std.heap.ArenaAllocator = std.heap.ArenaAllocator.init(std.heap.page_allocator),
mFrameAllocator: std.mem.Allocator = undefined,
//mEngineContext: EngineContext = .{}, //TODO: Implement this

/// Initializes the engine application.
///
/// Parameters:
/// - `self`: A pointer to the `Application` instance to initialize.
/// - `engine_allocator`: Allocator used for setting up subsystems.
///
/// Returns:
/// - `!void` on failure to initialize any core system returns the error else returns nothing.
pub fn Init(self: *Application) !void {
    self.mEngineAllocator = self.mEngineGPA.allocator();
    self.mFrameAllocator = self.mFrameArena.allocator();

    self.mWindow.Init();

    EngineContext.Init(&self.mWindow, self.mEngineAllocator, &self.mProgram, self);

    try self.mProgram.Init(self.mEngineAllocator, &self.mWindow, &self.mEngineContext);

    self.mWindow.SetVSync(false);
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
    SystemEventManager.Deinit();
    GameEventManager.Deinit();
    ImguiEventManager.Deinit();
    Input.Deinit();
    _ = self.mEngineGPA.deinit();
    self.mFrameArena.deinit();
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
        self.mEngineContext.mDT = delta_time;

        const zone = Tracy.ZoneInit("Main Loop", @src());
        defer zone.Deinit();

        try self.mProgram.OnUpdate(delta_time, &self.mEngineContext, self.mFrameAllocator);
        _ = self.mFrameArena.reset(.retain_capacity);

        Tracy.FrameMark();
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
        .ET_InputPressed => |e| try self.mProgram.OnInputPressedEvent(e, self.mFrameAllocator),
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
    _ = try self.mProgram.OnWindowResize(width, height, self.mFrameAllocator);
    return true;
}
