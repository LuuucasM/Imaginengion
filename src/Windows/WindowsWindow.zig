const std = @import("std");
const builtin = @import("builtin");

const Event = @import("../Events/Event.zig").Event;
const EventManager = @import("../Events/EventManager.zig");
const InputManager = @import("../Inputs/Input.zig");

const glfw = @import("../Core/CImports.zig").glfw;

const WindowsWindow = @This();

_Title: [*:0]const u8 = " ",
_Width: usize = 1600,
_Height: usize = 900,
_IsVSync: bool = true,
_WindowCount: usize = 0,
_Window: ?*glfw.struct_GLFWwindow = undefined,

pub fn Init(self: *WindowsWindow) void {
    if (self._WindowCount == 0) {
        _ = glfw.glfwSetErrorCallback(GLFWErrorCallback);
        const success: c_int = glfw.glfwInit();
        std.debug.assert(success != glfw.GLFW_FALSE);
    }

    if ((builtin.mode == .Debug) or (builtin.mode == .ReleaseSafe)) {
        glfw.glfwWindowHint(glfw.GLFW_OPENGL_DEBUG_CONTEXT, glfw.GLFW_TRUE);
    }

    self._Window = glfw.glfwCreateWindow(@intCast(self._Width), @intCast(self._Height), self._Title, null, null);
    if (self._Window == null) {
        @panic("Could not create glfw window in WindowsWindow::Init");
    }
    self._WindowCount += 1;

    _ = glfw.glfwSetWindowCloseCallback(self._Window, GLFWWindowCloseCallback);
    _ = glfw.glfwSetWindowSizeCallback(self._Window, GLFWWindowResizeCallback);
    _ = glfw.glfwSetKeyCallback(self._Window, GLFWKeyCallback);
    _ = glfw.glfwSetMouseButtonCallback(self._Window, GLFWMouseButtonCallback);
    _ = glfw.glfwSetCursorPosCallback(self._Window, GLFWMouseMovedCallback);
    _ = glfw.glfwSetScrollCallback(self._Window, GLFWMouseScrolledCallback);
}

pub fn Deinit(self: *WindowsWindow) void {
    if (self._Window) |window| {
        glfw.glfwDestroyWindow(window);
        self._WindowCount -= 1;
        if (self._WindowCount == 0) {
            glfw.glfwTerminate();
        }
    }
}

pub fn GetWidth(self: WindowsWindow) usize {
    return self._Width;
}

pub fn GetHeight(self: WindowsWindow) usize {
    return self._Height;
}

pub fn SetVSync(self: *WindowsWindow, useVSync: bool) void {
    if (useVSync == true) {
        glfw.glfwSwapInterval(1);
    } else {
        glfw.glfwSwapInterval(0);
    }
    self._IsVSync = useVSync;
}

pub fn IsVSync(self: WindowsWindow) bool {
    return self._IsVSync;
}

pub fn GetNativeWindow(self: WindowsWindow) *void {
    if (self._Window) |window| {
        return @ptrCast(window);
    }
    @panic("Can not GetNativeWindow before Window is created in WindowsWindow::GetNativeWindow\n");
}

pub fn OnWindowResize(self: *WindowsWindow, width: usize, height: usize) void {
    self._Width = width;
    self._Height = height;
}

export fn GLFWErrorCallback(err: c_int, msg: [*c]const u8) callconv(.C) void {
    std.log.err("GLFW Error ({}): {s} in WindowsWindow::GLFWErrorCallback\n", .{ err, msg });
}

export fn GLFWKeyCallback(window: ?*glfw.struct_GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.C) void {
    _ = window;
    _ = scancode;
    _ = mods;
    const new_event = switch (action) {
        glfw.GLFW_PRESS => blk: {
            InputManager.SetKeyPressed(@enumFromInt(key), true) catch |err| {
                std.log.err("{}\n", .{err});
                @panic("Cant set key pressed true in WindowsWindow::GLFWKeyCallback\n");
            };
            break :blk Event{
                .ET_KeyPressed = .{
                    ._KeyCode = @enumFromInt(key),
                    ._RepeatCount = 0,
                },
            };
        },
        glfw.GLFW_RELEASE => blk: {
            InputManager.SetKeyPressed(@enumFromInt(key), false) catch |err| {
                std.log.err("{}\n", .{err});
                @panic("Cant set key pressed false in WindowsWindow::GLFWKeyCallback\n");
            };
            break :blk Event{
                .ET_KeyReleased = .{
                    ._KeyCode = @enumFromInt(key),
                },
            };
        },
        glfw.GLFW_REPEAT => blk: {
            InputManager.SetKeyPressed(@enumFromInt(key), true) catch |err| {
                std.log.err("{}\n", .{err});
                @panic("Cant set key pressed true in WindowsWindow::GLFWKeyCallback\n");
            };
            break :blk Event{
                .ET_KeyPressed = .{
                    ._KeyCode = @enumFromInt(key),
                    ._RepeatCount = 1,
                },
            };
        },
        else => @panic("Unknown glfw action in Windowswindow::GLFWKeyCallback\n"),
    };
    EventManager.Insert(new_event) catch |err| {
        std.debug.print("{}\n", .{err});
        @panic("Could not insert event into queue in Windowswindow::GLFWKeyCallback\n");
    };
}

export fn GLFWMouseButtonCallback(window: ?*glfw.struct_GLFWwindow, button: c_int, action: c_int, mods: c_int) callconv(.C) void {
    _ = window;
    _ = mods;
    const new_event = switch (action) {
        glfw.GLFW_PRESS => blk: {
            InputManager.SetMousePressed(@enumFromInt(button), true) catch |err| {
                std.log.err("{}\n", .{err});
                @panic("Cant set mouse pressed true in WindowsWindow::GLFWMouseButtonCallback\n");
            };
            break :blk Event{
                .ET_MouseButtonPressed = .{
                    ._MouseCode = @enumFromInt(button),
                },
            };
        },

        glfw.GLFW_RELEASE => blk: {
            InputManager.SetMousePressed(@enumFromInt(button), false) catch |err| {
                std.log.err("{}\n", .{err});
                @panic("Cant set mouse pressed false in WindowsWindow::GLFWMouseBUtotnCallback\n");
            };
            break :blk Event{
                .ET_MouseButtonReleased = .{
                    ._MouseCode = @enumFromInt(button),
                },
            };
        },
        else => @panic("Unknown glfw action in Windowswindow::GLFWMouseButtonCallback\n"),
    };
    EventManager.Insert(new_event) catch |err| {
        std.debug.print("{}\n", .{err});
        @panic("Could not insert event into queue in Windowswindow::GLFWMouseButtonCallback\n");
    };
}

export fn GLFWMouseMovedCallback(window: ?*glfw.struct_GLFWwindow, xPos: f64, yPos: f64) callconv(.C) void {
    _ = window;
    InputManager.SetMousePosition(@Vector(2, f64){ xPos, yPos });
    const new_event = Event{
        .ET_MouseMoved = .{
            ._MouseX = @floatCast(xPos),
            ._MouseY = @floatCast(yPos),
        },
    };
    EventManager.Insert(new_event) catch |err| {
        std.debug.print("{}\n", .{err});
        @panic("Could not insert event into queue in Windowswindow::GLFWMouseMovedCallback");
    };
}

export fn GLFWMouseScrolledCallback(window: ?*glfw.struct_GLFWwindow, xOffset: f64, yOffset: f64) callconv(.C) void {
    _ = window;
    InputManager.SetMouseScrolled(@Vector(2, f64){ xOffset, yOffset });
    const new_event = Event{
        .ET_MouseScrolled = .{
            ._XOffset = @floatCast(xOffset),
            ._YOffset = @floatCast(yOffset),
        },
    };
    EventManager.Insert(new_event) catch |err| {
        std.debug.print("{}\n", .{err});
        @panic("Could not insert event into queue in Windowswindow::GLFWMouseScrolledCallback\n");
    };
}

export fn GLFWWindowCloseCallback(window: ?*glfw.struct_GLFWwindow) callconv(.C) void {
    _ = window;
    const new_event = Event{
        .ET_WindowClose = .{},
    };
    EventManager.Insert(new_event) catch |err| {
        std.debug.print("{}\n", .{err});
        @panic("Could not insert event into queue in Windowswindow::GLFWWindowCloseCallback\n");
    };
}

export fn GLFWWindowResizeCallback(window: ?*glfw.struct_GLFWwindow, width: c_int, height: c_int) callconv(.C) void {
    _ = window;
    const new_event = Event{
        .ET_WindowResize = .{
            ._Width = @intCast(width),
            ._Height = @intCast(height),
        },
    };
    EventManager.Insert(new_event) catch |err| {
        std.debug.print("{}\n", .{err});
        @panic("Could not insert event into queue in Windowswindow::GLFWWindowResizeCallback\n");
    };
}
