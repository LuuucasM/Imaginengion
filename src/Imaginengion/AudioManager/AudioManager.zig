const AudioContext = @import("AudioContext.zig");
const AudioManager = @This();

var ManagerInstance: AudioManager = .{};

mAudioContext: AudioContext = undefined,

pub fn Init() void {
    ManagerInstance.mAudioContext = AudioContext.Init();
}

pub fn Deinit() void {
    ManagerInstance.mAudioContext.Deinit();
}
