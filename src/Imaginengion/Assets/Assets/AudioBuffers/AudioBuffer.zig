const std = @import("std");
const builtin = @import("builtin");
const AudioBuffer = @This();

const Impl = switch (builtin.os.tag) {
    .windows => @import("MiniAudioBuffer.zig"),
    else => @import("NullAudioBuffer.zig"),
};

mImpl: Impl = .{},

pub fn Init(self: *AudioBuffer, rel_path: []const u8, asset_file: std.fs.File) !void {
    try self.mImpl.Init(rel_path, asset_file);
}

pub fn Deinit(self: *AudioBuffer) !void {
    try self.mImpl.Deinit();
}

pub fn ReadFrames(self: *AudioBuffer, frames_out: []f32, frame_count: u64, cursor: *u64, loop: bool) u64 {
    return self.mImpl.ReadFrames(frames_out, frame_count, cursor, loop);
}
