const std = @import("std");
const builtin = @import("builtin");
const AudioBuffer = @This();

const Impl = switch (builtin.os.tag) {
    .windows => @import("MiniAudioBuffer.zig"),
    else => @import("NullAudioBuffer.zig"),
};

mImpl: Impl,

pub fn Init(allocator: std.mem.Allocator, asset_file: std.fs.File) !AudioBuffer {
    return AudioBuffer{
        .mImpl = try Impl.Init(allocator, asset_file),
    };
}

pub fn Deinit(self: *AudioBuffer) !void {
    try self.mImpl.Deinit();
}
