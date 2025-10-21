const std = @import("std");
const ma = @import("../Core/CImports.zig").miniaudio;
const MiniAudioContext = @This();

const AUDIO_FORMAT = @import("AudioManager.zig").AUDIO_FORMAT;
const AUDIO_CHANNELS = @import("AudioManager.zig").AUDIO_CHANNELS;
const SAMPLE_RATE = @import("AudioManager.zig").SAMPLE_RATE;

const 

mDevice: ma.ma_device = undefined,

pub fn Init(self: *MiniAudioContext) !void {
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
    ma.ma_device_uninit(&self.mDevice);
}

fn DataCallback(device: [*c]ma.struct_ma_device, output: ?*anyopaque, input: ?*const anyopaque, frame_count: c_uint) callconv(.c) void {
    _ = device;
    _ = output;
    _ = input;
    _ = frame_count;
    //do the mixing
}
