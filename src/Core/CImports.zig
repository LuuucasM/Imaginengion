const builtin = @import("builtin");
pub const glad = @cImport({
    @cInclude("glad/glad.h");
});

pub const glfw = @cImport({
    @cInclude("GLFW/glfw3.h");
});

pub const imgui = @cImport({
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "");
    @cDefine("CIMGUI_USE_GLFW", "");
    @cDefine("CIMGUI_USE_OPENGL3", "");
    @cInclude("cimgui.h");
    @cInclude("cimgui_impl.h");
});

pub const windows = switch (builtin.os.tag) {
    .windows => @cImport({
        @cDefine("GLFW_EXPOSE_NATIVE_WIN32", "");
        @cInclude("GLFW/glfw3.h");
        @cInclude("GLFW/glfw3native.h");
        @cInclude("shlobj.h");
    }),
    else => undefined,
};
