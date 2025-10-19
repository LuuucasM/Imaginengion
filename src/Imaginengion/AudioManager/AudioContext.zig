const builtin = @import("builtin");
const AudioContext = @This();

const Impl = switch (builtin.os.tag) {
    .windows => @import("MiniAudioContext.zig"),
    else => @import("NullContext.zig"),
};

mImpl: Impl = .{},

pub fn Init(self: *AudioContext) !AudioContext {
    self.mImpl.Init();
}

pub fn Setup(self: *AudioContext) !void {
    try self.mImpl.Setup();
}

pub fn Deinit(self: *AudioContext) AudioContext {
    self.mImpl.Deinit();
}
