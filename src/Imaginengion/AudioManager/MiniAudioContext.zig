const std = @import("std");
const ma = @import("../Core/CImports.zig").miniaudio;
const SPSCRingBuffer = @import("../Core/SPSCRingBuffer.zig");
const MiniAudioContext = @This();

const AUDIO_FORMAT = @import("AudioManager.zig").AUDIO_FORMAT;
const AUDIO_CHANNELS = @import("AudioManager.zig").AUDIO_CHANNELS;
const SAMPLE_RATE = @import("AudioManager.zig").SAMPLE_RATE;
const BUFFER_CAPACITY = @import("AudioManager.zig").BUFFER_CAPACITY;

mDevice: ma.ma_device = undefined,

pub fn Init(self: *MiniAudioContext, audio_buffer: *SPSCRingBuffer(f32, BUFFER_CAPACITY)) !void {
    var device_config = ma.ma_device_config_init(ma.ma_device_type_playback);
    device_config.playback.format = AudioFormatToMAFormat(AUDIO_FORMAT);
    device_config.playback.channels = AUDIO_CHANNELS;
    device_config.sampleRate = SAMPLE_RATE;
    device_config.dataCallback = DataCallback;
    device_config.pUserData = audio_buffer;

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
    _ = input;

    const frames_buffer: *SPSCRingBuffer(f32, BUFFER_CAPACITY) = @ptrCast(@alignCast(device.*.pUserData.?));

    const needed_samples = frame_count * AUDIO_CHANNELS;

    const out_ptr = @as([*]f32, @ptrCast(@alignCast(output.?)));
    const out_slice = out_ptr[0..needed_samples];

    const num_popped = frames_buffer.PopSlice(out_slice);

    if (num_popped < needed_samples) {
        @memset(out_slice[num_popped..needed_samples], 0);
    }
}

fn AudioFormatToMAFormat(comptime format: type) c_uint {
    if (format == f32) {
        return ma.ma_format_f32;
    }
    @panic("Audio format not supported");
}
