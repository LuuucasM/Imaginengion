pub const c = @cImport({
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "");
    @cDefine("CIMGUI_USE_SDL3", "");
    @cDefine("CIMGUI_USE_SDLGPU", "");
    @cInclude("cimgui.h");
    @cInclude("generator/output/cimgui_impl.h");
});
