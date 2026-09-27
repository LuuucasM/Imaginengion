const std = @import("std");
const builtin = @import("builtin");
const EngineContext = @import("../../../Core/EngineContext.zig");
const AudioBuffer = @This();

const Impl = switch (builtin.os.tag) {
    .windows => @import("MiniAudioBuffer.zig"),
    else => @import("NullAudioBuffer.zig"),
};

mImpl: Impl = .{},

pub fn Init(self: *AudioBuffer, engine_context: *EngineContext, rel_path: []const u8, asset_file: std.Io.File) !void {
    try self.mImpl.Init(engine_context, rel_path, asset_file);
}

pub fn Deinit(self: *AudioBuffer) void {
    self.mImpl.Deinit();
}

pub fn GetFrameCount(self: AudioBuffer) u64 {
    return self.mImpl.GetFrameCount();
}

/// Every decoded sample, interleaved AUDIO_CHANNELS per frame
pub fn GetSamples(self: AudioBuffer) []const f32 {
    return self.mImpl.GetSamples();
}
