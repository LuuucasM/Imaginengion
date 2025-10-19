const std = @import("std");
const builtin = @import("builtin");
const AudioBuffer = @This();

const Impl = switch (builtin.os.tag) {
    .windows => @import("MiniAudioBuffer.zig"),
    else => @import("NullAudioBuffer.zig"),
};

mImpl: Impl = .{},

pub fn Init(self: *AudioBuffer, allocator: std.mem.Allocator, asset_file: std.fs.File) !void {
    try self.mImpl.Init(allocator, asset_file);
}

pub fn Setup(self: *AudioBuffer) !void {
    try self.mImpl.Setup();
}

pub fn Deinit(self: *AudioBuffer) !void {
    try self.mImpl.Deinit();
}
