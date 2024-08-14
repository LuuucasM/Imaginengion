const builtin = @import("builtin");
const UnsupportedPlatformUtils = @This();

pub fn OpenFolder() []const u16 {
    Unsupported();
}

pub fn OpenFile(filter: []const u8) []const u8 {
    _ = filter;
    Unsupported();
}
pub fn SaveFile(filter: []const u8) []const u8 {
    _ = filter;
    Unsupported();
}
fn Unsupported() noreturn {
    @compileError("Unsupported operating system: " ++ @tagName(builtin.os.tag) ++ " in PlatformUtils!");
}
