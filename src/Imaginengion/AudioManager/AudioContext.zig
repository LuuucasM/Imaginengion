const builtin = @import("builtin");
const AudioFrame = @import("AudioManager.zig").AudioFrame;
const SPSCRingBuffer = @import("../Core/SPSCRingBuffer.zig");
const BUFFER_CAPACITY = @import("AudioManager.zig").BUFFER_CAPACITY;
const tAudioBuffer = @import("AudioManager.zig").tAudioBuffer;
const AudioContext = @This();

const Impl = switch (builtin.os.tag) {
    .windows => @import("MiniAudioContext.zig"),
    else => @import("NullContext.zig"),
};

mImpl: Impl = .{},

pub fn Init(self: *AudioContext) !void {
    try self.mImpl.Init();
}
pub fn Deinit(self: *AudioContext) void {
    self.mImpl.Deinit();
}

pub fn SetAudioBuffer(self: *AudioContext, buffer: *tAudioBuffer) void {
    self.mImpl.SetAudioBuffer(buffer);
}
pub fn RemoveAudioBuffer(self: *AudioContext) void {
    self.mImpl.RemoveAudioBuffer();
}
