const std = @import("std");
const ma = @import("../Core/CImports.zig").miniaudio;
const MiniAudioContext = @This();

pub const AUDIO_FORMAT = ma.ma_format_f32;
pub const AUDIO_CHANNELS = 2;
pub const SAMPLE_RATE = 48000;

pub const AudioType = enum(u8) {
    Audio2D,
    Audio3D,
};

pub const UserData = extern struct {
    mBufferPtr: *anyopaque = undefined,
    mCount: u64 = 0,
};

pub const AudioEmission = extern struct {
    mAudioType: AudioType,
    buffer: *ma.ma_audio_buffer,
    offset: u32,
    volume: f32,
    pitch: f32,
    looping: bool,
};

mUserData: UserData = .{},
mEmissionBuffer: std.ArrayList(AudioEmission) = .{},
mDevice: ma.ma_device = undefined,

pub fn Init(self: *MiniAudioContext) !void {
    self.mUserData.mBufferPtr = self.mEmissionBuffer.items.ptr;

    var device_config = ma.ma_device_config_init(ma.ma_device_type_playback);
    device_config.playback.format = AUDIO_FORMAT;
    device_config.playback.channels = AUDIO_CHANNELS;
    device_config.sampleRate = SAMPLE_RATE;
    device_config.dataCallback = DataCallback;
    device_config.pUserData = &self.mUserData;

    if (ma.ma_device_init(null, &device_config, &self.mDevice) != ma.MA_SUCCESS) {
        return error.DeviceInitFail;
    }

    if (ma.ma_device_start(&self.mDevice) != ma.MA_SUCCESS) {
        return error.DeviceStartFail;
    }
}

pub fn Deinit(self: *MiniAudioContext) void {
    ma.ma_device_stop(&self.mDevice);
    ma.ma_device_uninit(&self.mDevice);
}

fn DataCallback(device: [*c]ma.struct_ma_device, output: ?*anyopaque, input: ?*const anyopaque, frame_count: c_uint) callconv(.c) void {
    //do the mixing
}
