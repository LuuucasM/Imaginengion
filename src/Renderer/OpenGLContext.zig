const std = @import("std");
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
