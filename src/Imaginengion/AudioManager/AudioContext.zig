const builtin = @import("builtin");
const miniaudio = @import("../Core/CImports.zig").miniaudio;
const AudioContext = @This();

const Impl = switch (builtin.os.tag) {
    .windows => @import("MiniAudioContext.zig"),
    else => @import("UnsupportedContext.zig"),
};

mContext: miniaudio.ma_engine,

pub fn Init() AudioContext {
    return AudioContext{
        .mContext = miniaudio.m
    }
}
pub fn Deinit() AudioContext {}
