const std = @import("std");
const ma = @import("../Core/CImports.zig").miniaudio;
const MiniAudioContext = @This();

const AUDIO_FORMAT = @import("AudioManager.zig").AUDIO_FORMAT;
const AUDIO_CHANNELS = @import("AudioManager.zig").AUDIO_CHANNELS;
const SAMPLE_RATE = @import("AudioManager.zig").SAMPLE_RATE;
const BUFFER_CAPACITY = @import("AudioManager.zig").BUFFER_CAPACITY;
const TAudioBuffer = @import("AudioManager.zig").TAudioBuffer;

pub const DeviceContext = struct {
    mUserData: std.atomic.Value(?*TAudioBuffer) = std.atomic.Value(?*TAudioBuffer).init(null),
};

mDevice: ma.ma_device = undefined,
mAudioContext: DeviceContext = .{},

pub fn Init(self: *MiniAudioContext) !void {
    var device_config = ma.ma_device_config_init(ma.ma_device_type_playback);
    device_config.playback.format = AudioFormatToMAFormat(AUDIO_FORMAT);
    device_config.playback.channels = AUDIO_CHANNELS;
    device_config.sampleRate = SAMPLE_RATE;
    device_config.dataCallback = DataCallback;
    device_config.pUserData = &self.mAudioContext;

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

pub fn SetAudioBuffer(self: *MiniAudioContext, buffer: *TAudioBuffer) void {
    self.mAudioContext.mUserData.store(buffer, .acquire);
}
pub fn RemoveAudioBuffer(self: *MiniAudioContext) void {
    self.mAudioContext.mUserData.store(null, .acquire);
}

fn DataCallback(device: [*c]ma.struct_ma_device, output: ?*anyopaque, input: ?*const anyopaque, frame_count: c_uint) callconv(.c) void {
    _ = input;

    const out_ptr = @as([*]f32, @ptrCast(@alignCast(output.?)));
    const needed_samples = frame_count * AUDIO_CHANNELS;
    const audio_context = @as(*DeviceContext, @ptrCast(@alignCast(device.*.pUserData.?)));
    if (audio_context.mUserData.load(.acquire)) |user_data| {
        const frames_buffer: *TAudioBuffer = @ptrCast(@alignCast(user_data));

        const out_slice = out_ptr[0..needed_samples];

        const num_popped = frames_buffer.PopSlice(out_slice);

        if (num_popped < needed_samples) {
            @memset(out_slice[num_popped..needed_samples], 0);
        }
    } else {
        @memset(out_ptr[0..needed_samples], 0);
    }
}

pub fn AudioFormatToMAFormat(comptime format: type) c_uint {
    if (format == f32) {
        return ma.ma_format_f32;
    }
    @panic("Audio format not supported");
}
