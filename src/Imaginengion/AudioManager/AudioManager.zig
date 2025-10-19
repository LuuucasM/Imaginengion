const AudioContext = @import("AudioContext.zig");
const AudioManager = @This();

var ManagerInstance: AudioManager = .{};

mAudioContext: AudioContext = .{},

pub fn Init() !void {
    ManagerInstance.mAudioContext = try AudioContext.Init();
    try ManagerInstance.mAudioContext.Setup();
}

pub fn Deinit() void {
    ManagerInstance.mAudioContext.Deinit();
}
