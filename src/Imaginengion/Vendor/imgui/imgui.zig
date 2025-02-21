pub const c = @cImport({
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "");
    @cDefine("CIMGUI_USE_GLFW", "");
    @cDefine("CIMGUI_USE_OPENGL3", "");
    @cInclude("cimgui.h");
    @cInclude("generator/output/cimgui_impl.h");
    @cInclude("cimguizmo.h");
});

pub usingnamespace c;
