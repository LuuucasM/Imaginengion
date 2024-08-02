const std = @import("std");
const builtin = @import("builtin");

const InputEvents = @import("../Events/InputEvents.zig");
const EventManager = @import("../Events/EventManager.zig");

const glfw = @import("../Core/CImports.zig").glfw;

const WindowsWindow = @This();

_Title: [*:0]const u8 = " ",
_Width: usize = 1280,
_Height: usize = 720,
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
        @panic("Could not create glfw window!");
    }
    self._WindowCount += 1;

    //_ = glfw.glfwSetWindowCloseCallback(self._Window, GLFWWindowCloseCallback);
    //_ = glfw.glfwSetWindowSizeCallback(self._Window, GLFWWindowResizeCallback);
    _ = glfw.glfwSetKeyCallback(self._Window, GLFWKeyCallback);
    //_ = glfw.glfwSetMouseButtonCallback(self._Window, GLFWMouseButtonCallback);
    //_ = glfw.glfwSetCursorPosCallback(self._Window, GLFWMouseMovedCallback);
    //_ = glfw.glfwSetScrollCallback(self._Window, GLFWMouseScrollCallback);
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
    @panic("Can not GetNativeWindow before Window is created!");
}

pub fn OnWindowResize(self: *WindowsWindow, width: usize, height: usize) void {
    self._Width = width;
    self._Height = height;
}

export fn GLFWErrorCallback(err: c_int, msg: [*c]const u8) callconv(.C) void {
    std.log.err("GLFW Error ({}): {s}", .{ err, msg });
}

//export fn GLFWWindowCloseCallback(window: ?*glfw.struct_GLFWwindow) callconv(.C) void {}

//export fn GLFWWindowResizeCallback(window: ?*glfw.struct_GLFWwindow, width: c_int, height: c_int) callconv(.C) void {}

export fn GLFWKeyCallback(window: ?*glfw.struct_GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.C) void {
    _ = window;
    _ = scancode;
    _ = mods;
    switch (action) {
        glfw.GLFW_PRESS => {
            const new_event = InputEvents.KeyPressedEvent{
                ._KeyCode = @enumFromInt(key),
                ._RepeatCount = 0,
            };
            EventManager.Insert(new_event) catch |err| {
                std.debug.print("{}", .{err});
                @panic("couldnt insert into event manager");
            };
        },
        glfw.GLFW_RELEASE => {
            const new_event = InputEvents.KeyReleasedEvent{
                ._KeyCode = @enumFromInt(key),
            };
            EventManager.Insert(new_event) catch |err| {
                std.debug.print("{}", .{err});
                @panic("could not insert into event manager");
            };
        },
        glfw.GLFW_REPEAT => {
            const new_event = InputEvents.KeyPressedEvent{
                ._KeyCode = @enumFromInt(key),
                ._RepeatCount = 1,
            };
            EventManager.Insert(new_event) catch |err| {
                std.debug.print("{}", .{err});
                @panic("could not insert into event manager");
            };
        },
        else => @panic("not a valid glfw key press !"),
    }
}

//export fn GLFWMouseButtonCallback(window: ?*glfw.struct_GLFWwindow, button: c_int, action: c_int, mods: c_int) callconv(.C) void {}

//export fn GLFWMouseMovedCallback(window: ?*glfw.struct_GLFWwindow, xPos: f64, yPos: f64) callconv(.C) void {}

//export fn GLFWMouseScrollCallback(window: ?*glfw.struct_GLFWwindow, xOffset: f64, yOffset: f64) callconv(.C) void {}
