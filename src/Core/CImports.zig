pub const glad = @cImport({
    @cInclude("glad/glad.h");
});

pub const glfw = @cImport({
    @cInclude("GLFW/glfw3.h");
});

pub const imgui = @cImport({
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "");
    @cInclude("cimgui.h");
});
