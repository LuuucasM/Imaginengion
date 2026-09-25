const std = @import("std");
const builtin = @import("builtin");
const WindowEvent = @import("../Events/WindowEventData.zig").Event;

const sdl = @import("../Core/CImports.zig").sdl;

const Tracy = @import("../Core/Tracy.zig");

const EngineContext = @import("../Core/EngineContext.zig");

const SDLWindow = @This();

_Title: []const u8 = "Imaginengion\x00",
_Width: usize = 1600,
_Height: usize = 900,
_Window: ?*sdl.SDL_Window = null,
mIsMinimized: bool = false,

pub fn Init(self: *SDLWindow, engine_context: *EngineContext) void {
    self._Window = sdl.SDL_CreateWindow(self._Title.ptr, @intCast(self._Width), @intCast(self._Height), sdl.SDL_WINDOW_RESIZABLE);
    std.debug.assert(self._Window != null);
    _ = sdl.SDL_SetPointerProperty(sdl.SDL_GetWindowProperties(self._Window), "engine", engine_context);
}

pub fn Deinit(self: *SDLWindow) void {
    std.debug.assert(self._Window != null);
    sdl.SDL_DestroyWindow(self._Window);
}

pub fn GetWidth(self: SDLWindow) usize {
    return self._Width;
}

pub fn GetHeight(self: SDLWindow) usize {
    return self._Height;
}

pub fn GetNativeWindow(self: SDLWindow) *sdl.SDL_Window {
    std.debug.assert(self._Window != null);
    return self._Window.?;
}

pub fn IsMinimized(self: SDLWindow) bool {
    return self.mIsMinimized;
}

/// Pixels per window coordinate. 1.0 means mouse positions, ImGui positions and render target
/// pixels are all the same unit.
pub fn GetPixelDensity(self: SDLWindow) f32 {
    return sdl.SDL_GetWindowPixelDensity(self._Window);
}

/// The OS content scale for the display the window is on, e.g. 1.5 at 150% Windows scaling.
pub fn GetDisplayScale(self: SDLWindow) f32 {
    return sdl.SDL_GetWindowDisplayScale(self._Window);
}

pub fn PollInputEvents(self: *SDLWindow, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("Window::PollInputEvents", @src());
    defer zone.Deinit();
    const input_manager = &engine_context.mInputManager;

    //the input manager is the polled state scripts read each frame, so it is kept in step with
    //the events here. mouse position and scroll are committed once after the loop so their
    //deltas cover the whole frame, and fall to zero on a frame with no motion.
    var final_mouse_pos = input_manager.GetMousePosition();
    var final_mouse_scroll = input_manager.GetMouseScrolled();

    var event: sdl.SDL_Event = undefined;
    while (sdl.SDL_PollEvent(&event)) {
        engine_context.mImguiManager.ProcessEvent(&event);
        switch (event.type) {
            sdl.SDL_EVENT_WINDOW_CLOSE_REQUESTED => {
                try engine_context.mSystemEventManager.Insert(
                    engine_context.EngineAllocator(),
                    .WindowEvent,
                    .{ .WindowClose = .{ ._Window = self } },
                );
            },
            sdl.SDL_EVENT_WINDOW_RESIZED => {
                try engine_context.mSystemEventManager.Insert(
                    engine_context.EngineAllocator(),
                    .WindowEvent,
                    .{ .WindowResize = .{ ._Width = @intCast(event.window.data1), ._Height = @intCast(event.window.data2) } },
                );
                self._Width = @intCast(event.window.data1);
                self._Height = @intCast(event.window.data2);
                if (self._Height < 1 or self._Width < 1) self.mIsMinimized = true else self.mIsMinimized = false;
            },
            sdl.SDL_EVENT_KEY_DOWN => {
                try input_manager.SetKeyPressed(@enumFromInt(event.key.scancode));
                if (event.key.repeat) {
                    try engine_context.mSystemEventManager.Insert(
                        engine_context.EngineAllocator(),
                        .InputEvent,
                        .{ .KeyboardPressed = .{ ._InputCode = @enumFromInt(event.key.scancode), ._Repeat = 1 } },
                    );
                } else {
                    try engine_context.mSystemEventManager.Insert(
                        engine_context.EngineAllocator(),
                        .InputEvent,
                        .{ .KeyboardPressed = .{ ._InputCode = @enumFromInt(event.key.scancode), ._Repeat = 0 } },
                    );
                }
            },
            sdl.SDL_EVENT_KEY_UP => {
                input_manager.SetKeyReleased(@enumFromInt(event.key.scancode));
                try engine_context.mSystemEventManager.Insert(
                    engine_context.EngineAllocator(),
                    .InputEvent,
                    .{ .KeyboardReleased = .{ ._InputCode = @enumFromInt(event.key.scancode) } },
                );
            },
            sdl.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                try input_manager.SetMousePressed(@enumFromInt(event.button.button), .{ .x = event.button.x, .y = event.button.y });
                try engine_context.mSystemEventManager.Insert(
                    engine_context.EngineAllocator(),
                    .InputEvent,
                    .{ .MousePressed = .{
                        ._ButtonCode = @enumFromInt(event.button.button),
                    } },
                );
            },
            sdl.SDL_EVENT_MOUSE_BUTTON_UP => {
                const was_click = input_manager.SetMouseReleased(@enumFromInt(event.button.button), .{ .x = event.button.x, .y = event.button.y });
                try engine_context.mSystemEventManager.Insert(
                    engine_context.EngineAllocator(),
                    .InputEvent,
                    .{ .MouseReleased = .{
                        ._ButtonCode = @enumFromInt(event.button.button),
                    } },
                );
                //SDL has no click event, only down and up. its `clicks` counts quick repeats (2 for a
                //double click) but can't tell a click from a drag, so the input manager decides that
                if (was_click) {
                    try engine_context.mSystemEventManager.Insert(
                        engine_context.EngineAllocator(),
                        .InputEvent,
                        .{ .MouseClicked = .{
                            ._ButtonCode = @enumFromInt(event.button.button),
                            ._MouseX = event.button.x,
                            ._MouseY = event.button.y,
                            ._Clicks = event.button.clicks,
                        } },
                    );
                }
            },
            sdl.SDL_EVENT_MOUSE_MOTION => {
                final_mouse_pos = .{ .x = event.motion.x, .y = event.motion.y };
                try engine_context.mSystemEventManager.Insert(
                    engine_context.EngineAllocator(),
                    .InputEvent,
                    .{ .MouseMoved = .{ ._MouseX = event.motion.x, ._MouseY = event.motion.y } },
                );
            },
            sdl.SDL_EVENT_MOUSE_WHEEL => {
                final_mouse_scroll = .{ .x = event.wheel.x, .y = event.wheel.y };
                try engine_context.mSystemEventManager.Insert(
                    engine_context.EngineAllocator(),
                    .InputEvent,
                    .{ .MouseScrolled = .{ ._XOffset = event.wheel.x, ._YOffset = event.wheel.y } },
                );
            },
            else => {},
        }
    }

    input_manager.SetMousePosition(final_mouse_pos);
    input_manager.SetMouseScrolled(final_mouse_scroll);
}
