const builtin = @import("builtin");
const AudioContext = @This();

const Impl = switch (builtin.os.tag) {
    .windows => @import("MiniAudioContext.zig"),
    else => @import("NullContext.zig"),
};

mImpl: Impl = undefined,

pub fn Init() !AudioContext {
    return AudioContext{
        .mImpl = try Impl.Init(),
    };
}

pub fn Setup(self: *AudioContext) !void {
    try self.mImpl.Setup();
}

pub fn Deinit(self: *AudioContext) AudioContext {
    self.mImpl.Deinit();
}
