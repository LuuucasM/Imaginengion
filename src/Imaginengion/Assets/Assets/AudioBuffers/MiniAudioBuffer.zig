const std = @import("std");
const ma = @import("../../../Core/CImports.zig").miniaudio;
const MiniAudioBuffer = @This();

const AUDIO_FORMAT = @import("../../../AudioManager/AudioManager.zig").AUDIO_FORMAT;
const AUDIO_CHANNELS = @import("../../../AudioManager/AudioManager.zig").AUDIO_CHANNELS;
const SAMPLE_RATE = @import("../../../AudioManager/AudioManager.zig").SAMPLE_RATE;
const AudioFormatToMAFormat = @import("../../../AudioManager/MiniAudioContext.zig").AudioFormatToMAFormat;

mAudioConfig: ma.ma_audio_buffer_config = undefined,
mPcmFrames: ?*anyopaque = null,
mFrameCount: u64 = 0,

pub fn Init(self: *MiniAudioBuffer, rel_path: []const u8, asset_file: std.fs.File) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var file_data: std.ArrayList(u8) = .{};
    const file_size = try asset_file.getEndPos();
    try file_data.ensureTotalCapacity(arena_allocator, file_size);
    file_data.expandToCapacity();

    _ = try asset_file.readAll(file_data.items);

    var decoder_config = ma.ma_decoder_config_init(AudioFormatToMAFormat(AUDIO_FORMAT), AUDIO_CHANNELS, SAMPLE_RATE);

    if (ma.ma_decode_memory(file_data.items.ptr, file_data.items.len, &decoder_config, &self.mFrameCount, &self.mPcmFrames) != ma.MA_SUCCESS) {
        std.log.err("Failed to decode memory for MiniAudioBuffer for file {s}!\n", .{rel_path});
        return error.AssetInitFail;
    }

    self.mAudioConfig = ma.ma_audio_buffer_config_init(AudioFormatToMAFormat(AUDIO_FORMAT), AUDIO_CHANNELS, self.mFrameCount, self.mPcmFrames, null);
}

pub fn Deinit(self: *MiniAudioBuffer) !void {
    std.debug.assert(self.mPcmFrames != null);
    ma.ma_free(self.mPcmFrames, null);
}

pub fn ReadFrames(self: *MiniAudioBuffer, frames_out: []f32, cursor: *u64, loop: bool) u64 {
    std.debug.assert(self.mPcmFrames != null);
    std.debug.assert(self.mFrameCount > 0);
    std.debug.assert(cursor.* <= self.mFrameCount);
    std.debug.assert(frames_out.len % self.mAudioConfig.channels == 0);

    if (frames_out.len == 0) return 0;

    const pcm_data = @as([*]const f32, @ptrCast(@alignCast(self.mPcmFrames.?)));
    const channels = @as(usize, @intCast(self.mAudioConfig.channels));
    const frames_requested = frames_out.len / channels;

    if (cursor.* >= self.mFrameCount) {
        if (!loop) return 0;
        cursor.* = 0;
    }

    const frames_available = self.mFrameCount - cursor.*;
    const first_frames = @min(frames_requested, frames_available);
    const first_samples = first_frames * channels;

    const start_sample_ind = cursor.* * channels;
    const end_sample_ind = (cursor.* + first_frames) * channels;

    @memcpy(frames_out[0..first_samples], pcm_data[start_sample_ind..end_sample_ind]);

    cursor.* += first_frames;

    var total_frames = first_frames;

    if (loop and first_frames < frames_requested) {
        cursor.* = 0;

        const remaining_frames = frames_requested - first_frames;
        const second_frames = @min(remaining_frames, self.mFrameCount);
        const second_samples = second_frames * channels;

        @memcpy(frames_out[first_samples .. first_samples + second_samples], pcm_data[0..second_samples]);

        cursor.* = second_frames;
        total_frames += second_frames;
    }

    return total_frames;
}
