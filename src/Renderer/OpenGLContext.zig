const std = @import("std");
const Application = @import("../Core/Application.zig");

const glad = @import("../Core/CImports.zig").glad;
const glfw = @import("../Core/CImports.zig").glfw;

const OpenGLContext = @This();

_Window: ?*glfw.struct_GLFWwindow = undefined,

pub fn Init(self: *OpenGLContext) void {
    self._Window = @ptrCast(Application.GetNativeWindow());

    glfw.glfwMakeContextCurrent(self._Window);
    const procaddr: glad.GLADloadproc = @ptrCast(&glfw.glfwGetProcAddress);
    const success: c_int = glad.gladLoadGLLoader(procaddr);
    std.debug.assert(success == 1);

    std.log.info("OpenGL Info: \n", .{});
    std.log.info("\tVendor: {s}\n", .{glad.glGetString(glad.GL_VENDOR)});
    std.log.info("\tRenderer: {s}\n", .{glad.glGetString(glad.GL_RENDERER)});
    std.log.info("\tVersion: {s}\n", .{glad.glGetString(glad.GL_VERSION)});
}

pub fn SwapBuffers(self: OpenGLContext) void {
    glfw.glfwSwapBuffers(self._Window);
}
