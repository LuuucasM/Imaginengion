const std = @import("std");
const builtin = @import("builtin");
const PlatformUtils = @This();

const Impl = switch (builtin.os.tag) {
    .windows => @import("WindowsPlatformUtils.zig"),
    else => @import("UnsupportedPlatformUtils.zig"),
};

pub fn OpenFile(filter: []const u8) []const u8 {
    Impl.OpenFile(filter);
}

pub fn SaveFile(filter: []const u8) []const u8 {
    Impl.SaveFile(filter);
}
