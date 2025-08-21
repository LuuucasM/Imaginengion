pub const c = @cImport({
    @cDefine("TRACY_ENABLE", "1");
    @cInclude("tracy/TracyC.h");
});
