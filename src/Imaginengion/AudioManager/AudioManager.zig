const std = @import("std");
const AudioContext = @import("AudioContext.zig");
const Audio2D = @import("Audio2D.zig");
const Audio3D = @import("Audio3D.zig");
const AudioFrameBuffer = @import("AudioFrameBuffer.zig").AudioFrameBuffer;
const AudioManager = @This();

pub const AUDIO_FORMAT = f32;
pub const AUDIO_CHANNELS = 2;
pub const SAMPLE_RATE = 48000;

pub const AudioStats = struct {
    mAudioEmissionNum: u32 = 0,
};

var AudioGPA = std.heap.DebugAllocator(.{}).init;
const AudioAllocator = AudioGPA.allocator();

var ManagerInstance: AudioManager = .{};

mAudioStats: AudioStats = .{},
mAudioContext: AudioContext = .{},
mA2D: Audio2D = .{},
mA3D: Audio3D = .{},
mFrameBuffers: AudioFrameBuffer = .{ .E_DoubleBuffer = .{} },

pub fn Init() !void {
    try ManagerInstance.mAudioContext.Init(&ManagerInstance.mFrameBuffers);
    ManagerInstance.mA2D.Init();
    ManagerInstance.mA3D.Init();
    ManagerInstance.mFrameBuffers.Init();
}

pub fn Deinit() void {
    ManagerInstance.mAudioContext.Deinit();
    ManagerInstance.mA2D.Deinit();
    ManagerInstance.mA3D.Deinit();
    ManagerInstance.mFrameBuffers.Deinit();
}

pub fn OnUpdate() void {
    const write_buffer = ManagerInstance.mFrameBuffers.GetWriteBuffer();
    defer ManagerInstance.mFrameBuffers.FinishWriting();

    //do work
    _ = write_buffer;
}
