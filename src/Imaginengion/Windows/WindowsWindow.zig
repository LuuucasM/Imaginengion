const std = @import("std");
const builtin = @import("builtin");
const Vec2f32 = @import("../Math/LinAlg.zig").Vec2f32;
const SystemEvent = @import("../Events/SystemEvent.zig").SystemEvent;

const glfw = @import("../Core/CImports.zig").glfw;

const Tracy = @import("../Core/Tracy.zig");

const EngineContext = @import("../Core/EngineContext.zig");

const WindowsWindow = @This();

_Title: []const u8 = "Imaginengion\x00",
_Width: usize = 1600,
_Height: usize = 900,
_IsVSync: bool = true,
_Window: ?*glfw.struct_GLFWwindow = null,

pub fn Init(self: *WindowsWindow, engine_context: *EngineContext) void {
    _ = glfw.glfwSetErrorCallback(GLFWErrorCallback);
    const success: c_int = glfw.glfwInit();
    std.debug.assert(success != glfw.GLFW_FALSE);

    glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MAJOR, 4);
    glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MINOR, 6);
    glfw.glfwWindowHint(glfw.GLFW_OPENGL_DEBUG_CONTEXT, glfw.GLFW_TRUE);

    self._Window = glfw.glfwCreateWindow(@intCast(self._Width), @intCast(self._Height), self._Title.ptr, null, null);
    std.debug.assert(self._Window != null);

    glfw.glfwSetWindowUserPointer(self._Window, engine_context);

    _ = glfw.glfwSetWindowCloseCallback(self._Window, GLFWWindowCloseCallback);
    _ = glfw.glfwSetWindowSizeCallback(self._Window, GLFWWindowResizeCallback);
    _ = glfw.glfwSetKeyCallback(self._Window, GLFWKeyCallback);
    _ = glfw.glfwSetMouseButtonCallback(self._Window, GLFWMouseButtonCallback);
    _ = glfw.glfwSetCursorPosCallback(self._Window, GLFWMouseMovedCallback);
    _ = glfw.glfwSetScrollCallback(self._Window, GLFWMouseScrolledCallback);
}

pub fn Deinit(self: *WindowsWindow) void {
    glfw.glfwDestroyWindow(self._Window);
    glfw.glfwTerminate();
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

pub fn GetNativeWindow(self: WindowsWindow) *anyopaque {
    if (self._Window) |window| {
        return @ptrCast(window);
    }
    @panic("Can not GetNativeWindow before Window is created in WindowsWindow::GetNativeWindow\n");
}

pub fn OnWindowResize(self: *WindowsWindow, width: usize, height: usize) void {
    self._Width = width;
    self._Height = height;
}

pub fn PollInputEvents(self: WindowsWindow) void {
    const zone = Tracy.ZoneInit("PollInputEvents", @src());
    defer zone.Deinit();
    _ = self;
    glfw.glfwPollEvents();
}

export fn GLFWErrorCallback(err: c_int, msg: [*c]const u8) callconv(.c) void {
    std.log.err("GLFW Error ({}): {s} in WindowsWindow::GLFWErrorCallback\n", .{ err, msg });
}

export fn GLFWKeyCallback(window: ?*glfw.struct_GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.c) void {
    const engine_context: *EngineContext = @ptrCast(@alignCast(glfw.glfwGetWindowUserPointer(window)));

    _ = scancode;
    _ = mods;
    const new_event = switch (action) {
        glfw.GLFW_PRESS => blk: {
            break :blk SystemEvent{
                .ET_InputPressed = .{
                    ._InputCode = @enumFromInt(key),
                    ._Repeat = 0,
                },
            };
        },
        glfw.GLFW_RELEASE => blk: {
            break :blk SystemEvent{
                .ET_InputReleased = .{
                    ._InputCode = @enumFromInt(key),
                },
            };
        },
        glfw.GLFW_REPEAT => blk: {
            break :blk SystemEvent{
                .ET_InputPressed = .{
                    ._InputCode = @enumFromInt(key),
                    ._Repeat = 1,
                },
            };
        },
        else => @panic("Unknown glfw action in Windowswindow::GLFWKeyCallback\n"),
    };
    engine_context.mSystemEventManager.Insert(engine_context.EngineAllocator(), new_event) catch |err| {
        std.debug.print("{}\n", .{err});
        @panic("Could not insert event into queue in Windowswindow::GLFWKeyCallback\n");
    };
}

export fn GLFWMouseButtonCallback(window: ?*glfw.struct_GLFWwindow, button: c_int, action: c_int, mods: c_int) callconv(.c) void {
    const engine_context: *EngineContext = @ptrCast(@alignCast(glfw.glfwGetWindowUserPointer(window)));

    _ = mods;
    const new_event = switch (action) {
        glfw.GLFW_PRESS => blk: {
            break :blk SystemEvent{
                .ET_InputPressed = .{
                    ._InputCode = @enumFromInt(button),
                    ._Repeat = 0,
                },
            };
        },

        glfw.GLFW_RELEASE => blk: {
            break :blk SystemEvent{
                .ET_InputReleased = .{
                    ._InputCode = @enumFromInt(button),
                },
            };
        },
        else => @panic("Unknown glfw action in Windowswindow::GLFWMouseButtonCallback\n"),
    };
    engine_context.mSystemEventManager.Insert(engine_context.EngineAllocator(), new_event) catch |err| {
        std.debug.print("{}\n", .{err});
        @panic("Could not insert event into queue in Windowswindow::GLFWMouseButtonCallback\n");
    };
}

export fn GLFWMouseMovedCallback(window: ?*glfw.struct_GLFWwindow, xPos: f64, yPos: f64) callconv(.c) void {
    const engine_context: *EngineContext = @ptrCast(@alignCast(glfw.glfwGetWindowUserPointer(window)));

    const new_event = SystemEvent{
        .ET_MouseMoved = .{
            ._MouseX = @floatCast(xPos),
            ._MouseY = @floatCast(yPos),
        },
    };
    engine_context.mSystemEventManager.Insert(engine_context.EngineAllocator(), new_event) catch |err| {
        std.debug.print("{}\n", .{err});
        @panic("Could not insert event into queue in Windowswindow::GLFWMouseMovedCallback");
    };
}

export fn GLFWMouseScrolledCallback(window: ?*glfw.struct_GLFWwindow, xOffset: f64, yOffset: f64) callconv(.c) void {
    const engine_context: *EngineContext = @ptrCast(@alignCast(glfw.glfwGetWindowUserPointer(window)));
    const new_event = SystemEvent{
        .ET_MouseScrolled = .{
            ._XOffset = @floatCast(xOffset),
            ._YOffset = @floatCast(yOffset),
        },
    };
    engine_context.mSystemEventManager.Insert(engine_context.EngineAllocator(), new_event) catch |err| {
        std.debug.print("{}\n", .{err});
        @panic("Could not insert event into queue in Windowswindow::GLFWMouseScrolledCallback\n");
    };
}

export fn GLFWWindowCloseCallback(window: ?*glfw.struct_GLFWwindow) callconv(.c) void {
    const engine_context: *EngineContext = @ptrCast(@alignCast(glfw.glfwGetWindowUserPointer(window)));
    const new_event = SystemEvent{
        .ET_WindowClose = .{},
    };
    engine_context.mSystemEventManager.Insert(engine_context.EngineAllocator(), new_event) catch |err| {
        std.debug.print("{}\n", .{err});
        @panic("Could not insert event into queue in Windowswindow::GLFWWindowCloseCallback\n");
    };
}

export fn GLFWWindowResizeCallback(window: ?*glfw.struct_GLFWwindow, width: c_int, height: c_int) callconv(.c) void {
    const engine_context: *EngineContext = @ptrCast(@alignCast(glfw.glfwGetWindowUserPointer(window)));
    const new_event = SystemEvent{
        .ET_WindowResize = .{
            ._Width = @intCast(width),
            ._Height = @intCast(height),
        },
    };
    engine_context.mSystemEventManager.Insert(engine_context.EngineAllocator(), new_event) catch |err| {
        std.debug.print("{}\n", .{err});
        @panic("Could not insert event into queue in Windowswindow::GLFWWindowResizeCallback\n");
    };
}
