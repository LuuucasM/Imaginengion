const std = @import("std");
const builtin = @import("builtin");
const Application = @import("../Core/Application.zig");

const glad = @import("../Core/CImports.zig").glad;
const glfw = @import("../Core/CImports.zig").glfw;

const OpenGLContext = @This();

_Window: ?*glfw.struct_GLFWwindow,

pub fn Init() OpenGLContext {
    const window: ?*glfw.struct_GLFWwindow = @ptrCast(Application.GetWindow().GetNativeWindow());

    glfw.glfwMakeContextCurrent(window);
    const procaddr: glad.GLADloadproc = @ptrCast(&glfw.glfwGetProcAddress);
    const success: c_int = glad.gladLoadGLLoader(procaddr);
    std.debug.assert(success == @as(c_int, 1));

    if ((builtin.mode == .Debug) or (builtin.mode == .ReleaseSafe)) {
        glad.glEnable(glad.GL_DEBUG_OUTPUT);
        glad.glEnable(glad.GL_DEBUG_OUTPUT_SYNCHRONOUS);
        glad.glDebugMessageCallback(glDebugOutput, null);
        glad.glDebugMessageControl(glad.GL_DONT_CARE, glad.GL_DONT_CARE, glad.GL_DONT_CARE, 0, null, glad.GL_TRUE);
    }

    std.log.info("OpenGL Info: \n", .{});
    std.log.info("\tVendor: {s}\n", .{glad.glGetString(glad.GL_VENDOR)});
    std.log.info("\tRenderer: {s}\n", .{glad.glGetString(glad.GL_RENDERER)});
    std.log.info("\tVersion: {s}\n", .{glad.glGetString(glad.GL_VERSION)});

    return OpenGLContext{
        ._Window = window,
    };
}

pub fn SwapBuffers(self: OpenGLContext) void {
    glfw.glfwSwapBuffers(self._Window);
}

fn glDebugOutput(source: c_uint, debug_type: c_uint, id: c_uint, severity: c_uint, length: c_int, message: [*c]const u8, userParam: ?*const anyopaque) callconv(.C) void {
    _ = length;
    _ = userParam;
    _ = id;

    switch (severity) {
        //glad.GL_DEBUG_SEVERITY_NOTIFICATION => std.log.debug(
        //    "GL Debug: type = {s}, source = {s}, message = {s}\n",
        //    .{ glDebugTypeToStr(debug_type), glSourceToStr(source), message },
        //),

        //glad.GL_DEBUG_SEVERITY_LOW => std.log.info(
        //    "GL Debug: type = {s}, source = {s}, message = {s}\n",
        //    .{ glDebugTypeToStr(debug_type), glSourceToStr(source), message },
        //),

        glad.GL_DEBUG_SEVERITY_MEDIUM => std.log.warn(
            "GL Debug: type = {s}, source = {s}, message = {s}\n",
            .{ glDebugTypeToStr(debug_type), glSourceToStr(source), message },
        ),

        glad.GL_DEBUG_SEVERITY_HIGH => std.log.err(
            "GL Debug: type = {s}, source = {s}, message = {s}\n",
            .{ glDebugTypeToStr(debug_type), glSourceToStr(source), message },
        ),

        else => {},
    }
}

fn glDebugTypeToStr(debug_type: c_uint) []const u8 {
    return switch (debug_type) {
        glad.GL_DEBUG_TYPE_ERROR => "ERROR",
        glad.GL_DEBUG_TYPE_DEPRECATED_BEHAVIOR => "DEPRECATED_BEHAVIOR",
        glad.GL_DEBUG_TYPE_UNDEFINED_BEHAVIOR => "UNDEFINED_BEHAVIOR",
        glad.GL_DEBUG_TYPE_PORTABILITY => "PORTABILITY",
        glad.GL_DEBUG_TYPE_PERFORMANCE => "PERFORMANCE",
        glad.GL_DEBUG_TYPE_MARKER => "MARKER",
        glad.GL_DEBUG_TYPE_PUSH_GROUP => "PUSH_GROUP",
        glad.GL_DEBUG_TYPE_POP_GROUP => "POP_GROUP",
        glad.GL_DEBUG_TYPE_OTHER => "OTHER",
        else => "UNKNOWN",
    };
}

fn glSourceToStr(source: c_uint) []const u8 {
    return switch (source) {
        glad.GL_DEBUG_SOURCE_API => "API",
        glad.GL_DEBUG_SOURCE_WINDOW_SYSTEM => "WINDOW_SYSTEM",
        glad.GL_DEBUG_SOURCE_SHADER_COMPILER => "SHADER_COMPILER",
        glad.GL_DEBUG_SOURCE_THIRD_PARTY => "THIRD_PARTY",
        glad.GL_DEBUG_SOURCE_APPLICATION => "APPLICATION",
        glad.GL_DEBUG_SOURCE_OTHER => "OTHER",
        else => "UNKNOWN",
    };
}
