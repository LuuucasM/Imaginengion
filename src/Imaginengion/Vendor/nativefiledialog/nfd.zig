pub const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("nfd.h");
});

pub usingnamespace c;
