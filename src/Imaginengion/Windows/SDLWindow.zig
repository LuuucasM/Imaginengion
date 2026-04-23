const std = @import("std");
const builtin = @import("builtin");
const Vec2f32 = @import("../Math/LinAlg.zig").Vec2f32;
const WindowEvent = @import("../Events/WindowEventData.zig").Event;

const sdl = @import("../Core/CImports.zig").sdl;

const Tracy = @import("../Core/Tracy.zig");

const EngineContext = @import("../Core/EngineContext.zig");

const SDLWindow = @This();

_Title: []const u8 = "Imaginengion\x00",
_Width: usize = 1600,
_Height: usize = 900,
_Window: *sdl.SDL_Window = undefined,
mIsMinimized: bool = false,

pub fn Init(self: *SDLWindow, engine_context: *EngineContext) void {
    self._Window = sdl.SDL_CreateWindow(self._Title.ptr, @intCast(self._Width), @intCast(self._Height), sdl.SDL_WINDOW_RESIZABLE) orelse unreachable;
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
    return self._Window;
}

pub fn IsMinimized(self: SDLWindow) bool {
    return self.mIsMinimized;
}

pub fn PollInputEvents(self: SDLWindow, engine_context: *EngineContext) void {
    const zone = Tracy.ZoneInit("PollInputEvents", @src());
    defer zone.Deinit();
    var event: sdl.SDL_Event = undefined;
    while (sdl.SDL_PollEvent(&event) != 0) {
        switch (event.type) {
            sdl.SDL_EVENT_WINDOW_CLOSE_REQUESTED => {
                engine_context.mSystemEventManager.Insert(
                    engine_context.EngineAllocator(),
                    .WindowEvent,
                    .{ .WindowClose = .{ ._Window = self } },
                );
            },
            sdl.SDL_EVENT_WINDOW_RESIZED => {
                engine_context.mSystemEventManager.Insert(
                    engine_context.EngineAllocator(),
                    .WindowEvent,
                    .{ .WindowResize = .{ ._Width = event.window.data1, ._Height = event.window.data2 } },
                );
                self._Width = event.window.data1;
                self._Height = event.window.data2;
                if (self._Height < 1 or self._Width < 1) self.mIsMinimized = true else self.mIsMinimized = false;
            },
            sdl.SDL_EVENT_KEY_DOWN => {
                if (event.key.repeat) {
                    engine_context.mSystemEventManager.Insert(
                        engine_context.EngineAllocator(),
                        .InputEvent,
                        .{ .KeyboardPressed = .{ ._InputCode = @enumFromInt(event.key.scancode), ._Repeat = 1 } },
                    );
                } else {
                    engine_context.mSystemEventManager.Insert(
                        engine_context.EngineAllocator(),
                        .InputEvent,
                        .{ .KeyboardPressed = .{ ._InputCode = @enumFromInt(event.key.scancode), ._Repeat = 0 } },
                    );
                }
            },
            sdl.SDL_EVENT_KEY_UP => {
                engine_context.mSystemEventManager.Insert(
                    engine_context.EngineAllocator(),
                    .InputEvent,
                    .{ .KeyboardReleased = .{ ._InputCode = @enumFromInt(event.key.scancode) } },
                );
            },
            sdl.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                if (event.button.down) {}
                engine_context.mSystemEventManager.Insert(
                    engine_context.EngineAllocator(),
                    .InputEvent,
                    .{ .MousePressed = .{
                        ._ButtonCode = @enumFromInt(event.button.button),
                    } },
                );
            },
            sdl.SDL_EVENT_MOUSE_MOTION => {
                engine_context.mSystemEventManager.Insert(
                    engine_context.EngineAllocator(),
                    .InputEvent,
                    .{ .MouseMoved = .{ ._MouseX = event.motion.x, ._MouseY = event.motion.y } },
                );
            },
            sdl.SDL_EVENT_MOUSE_WHEEL => {
                engine_context.mSystemEventManager.Insert(
                    engine_context.EngineAllocator(),
                    .InputEvent,
                    .{ .MouseScrolled = .{ ._XOffset = event.wheel.x, ._YOffset = event.wheel.y } },
                );
            },
        }
    }
}
