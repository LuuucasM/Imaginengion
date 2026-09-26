const builtin = @import("builtin");
const TAudioBuffer = @import("AudioManager.zig").TAudioBuffer;
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

pub fn SetAudioBuffer(self: *AudioContext, buffer: *TAudioBuffer) void {
    self.mImpl.SetAudioBuffer(buffer);
}
pub fn RemoveAudioBuffer(self: *AudioContext) void {
    self.mImpl.RemoveAudioBuffer();
}

/// How many times the device asked for audio and the output buffer did not have enough, since Init
pub fn GetUnderrunCount(self: *AudioContext) u32 {
    return self.mImpl.GetUnderrunCount();
}
