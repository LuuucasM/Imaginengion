const std = @import("std");
const builtin = @import("builtin");
const UnsupportedPlatformUtils = @This();

pub fn OpenFolder(allocator: std.mem.Allocator) []const u16 {
    _ = allocator;
    Unsupported();
}

pub fn OpenFile(allocator: std.heap.page_allocator, filter: []const u8) []const u8 {
    _ = allocator;
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
