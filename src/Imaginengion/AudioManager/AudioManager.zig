const std = @import("std");
const AudioContext = @import("AudioContext.zig");
const Audio2D = @import("Audio2D.zig");
const Audio3D = @import("Audio3D.zig");
const RingBuffer = @import("../Core/RingBuffer.zig");
const AudioManager = @This();

pub const AUDIO_FORMAT = f32;
pub const AUDIO_CHANNELS = 2;
pub const SAMPLE_RATE = 48000;

pub const AudioStats = struct {
    mAudioEmissionNum: u32 = 0,
};

pub const AudioFrame = struct {
    Emissions2D: Audio2D.Emissions2D,
    //Emissions3D: Audio3D.Emissions3D,
    //maybe a variable like "is in use" that i can check to see if the audio thread is using it
    //if it is i can skip and write to the next in the ring instead
    //same goes with from the audio thread, if it trys to read te next one but its in use it goes to the next and reads the next one
};

pub const FrameRing = RingBuffer(AudioFrame, 3);

var ManagerInstance: AudioManager = .{};

mAudioStats: AudioStats = .{},
mAudioContext: AudioContext = .{},
mA2D: Audio2D = .{},
mA3D: Audio3D = .{},
mFrameRing: FrameRing,

pub fn Init() !void {
    try ManagerInstance.mAudioContext.Init();
    ManagerInstance.mA2D.Init();
    ManagerInstance.mA3D.Init();
}

pub fn Deinit() void {
    ManagerInstance.mAudioContext.Deinit();
    ManagerInstance.mA2D.Deinit();
    ManagerInstance.mA3D.Deinit();
}
