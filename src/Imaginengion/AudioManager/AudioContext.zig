const builtin = @import("builtin");
const AudioFrame = @import("AudioManager.zig").AudioFrame;
const AudioFrameBuffer = @import("AudioFrameBuffer.zig").AudioFrameBuffer;
const AudioContext = @This();

const Impl = switch (builtin.os.tag) {
    .windows => @import("MiniAudioContext.zig"),
    else => @import("NullContext.zig"),
};

mImpl: Impl = .{},

pub fn Init(self: *AudioContext, frame_buffers: *AudioFrameBuffer) !AudioContext {
    try self.mImpl.Init(frame_buffers);
}

pub fn Setup(self: *AudioContext) !void {
    try self.mImpl.Setup();
}

pub fn Deinit(self: *AudioContext) AudioContext {
    self.mImpl.Deinit();
}
