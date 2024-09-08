const std = @import("std");
const builtin = @import("builtin");
const PlatformUtils = @This();

const Impl = switch (builtin.os.tag) {
    .windows => @import("WindowsPlatformUtils.zig"),
    else => @import("UnsupportedPlatformUtils.zig"),
};

pub fn OpenFolder(allocator: std.mem.Allocator) ![]const u8 {
    return Impl.OpenFolder(allocator);
}

pub fn OpenFile(allocator: std.mem.Allocator, filter: []const u8) ![]const u8 {
    return Impl.OpenFile(allocator, filter);
}

pub fn SaveFile(filter: []const u8) []const u8 {
    return Impl.SaveFile(filter);
}
