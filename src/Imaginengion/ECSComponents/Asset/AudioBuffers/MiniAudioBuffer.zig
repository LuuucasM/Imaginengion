const std = @import("std");
const ma = @import("../../../Core/CImports.zig").miniaudio;
const EngineContext = @import("../../../Core/EngineContext.zig");
const MiniAudioBuffer = @This();

const AUDIO_FORMAT = @import("../../../AudioManager/AudioManager.zig").AUDIO_FORMAT;
const AUDIO_CHANNELS = @import("../../../AudioManager/AudioManager.zig").AUDIO_CHANNELS;
const SAMPLE_RATE = @import("../../../AudioManager/AudioManager.zig").SAMPLE_RATE;
const AudioFormatToMAFormat = @import("../../../AudioManager/MiniAudioContext.zig").AudioFormatToMAFormat;

//decoded straight to the output format (AUDIO_FORMAT, AUDIO_CHANNELS interleaved, SAMPLE_RATE), so reading
//is a plain copy. mono files get upmixed to stereo here, which will need revisiting for 3D sources
mPcmFrames: ?*anyopaque = null,
mFrameCount: u64 = 0,

pub fn Init(self: *MiniAudioBuffer, engine_context: *EngineContext, rel_path: []const u8, asset_file: std.Io.File) !void {
    const frame_allocator = engine_context.FrameAllocator();

    var file_reader = asset_file.reader(engine_context.Io(), &.{});
    const contents = try file_reader.interface.allocRemaining(frame_allocator, .unlimited);

    var decoder_config = ma.ma_decoder_config_init(AudioFormatToMAFormat(AUDIO_FORMAT), AUDIO_CHANNELS, SAMPLE_RATE);

    if (ma.ma_decode_memory(contents.ptr, contents.len, &decoder_config, &self.mFrameCount, &self.mPcmFrames) != ma.MA_SUCCESS) {
        std.log.err("Failed to decode memory for MiniAudioBuffer for file {s}!\n", .{rel_path});
        return error.AssetInitFailed;
    }

    if (self.mFrameCount == 0) {
        std.log.err("Audio file {s} decoded to 0 frames!\n", .{rel_path});
        ma.ma_free(self.mPcmFrames, null);
        self.mPcmFrames = null;
        return error.AssetInitFailed;
    }
}

pub fn Deinit(self: *MiniAudioBuffer) void {
    std.debug.assert(self.mPcmFrames != null);
    ma.ma_free(self.mPcmFrames, null);
}

pub fn GetFrameCount(self: MiniAudioBuffer) u64 {
    return self.mFrameCount;
}

/// Copies as many frames as fit in frames_out starting at cursor, and moves cursor past them. With loop set it
/// keeps wrapping back to the start until frames_out is full, however short the sound. Without it, it stops at
/// the end and returns fewer frames than asked for, and 0 once the sound is done.
pub fn ReadFrames(self: *MiniAudioBuffer, frames_out: []f32, cursor: *u64, loop: bool) u64 {
    std.debug.assert(self.mPcmFrames != null);
    std.debug.assert(frames_out.len % AUDIO_CHANNELS == 0);

    const pcm_data = @as([*]const f32, @ptrCast(@alignCast(self.mPcmFrames.?)));
    const frames_requested = frames_out.len / AUDIO_CHANNELS;

    //a hot reload can swap in a shorter file under a playing voice
    if (cursor.* > self.mFrameCount) cursor.* = self.mFrameCount;

    var frames_written: u64 = 0;
    while (frames_written < frames_requested) {
        if (cursor.* == self.mFrameCount) {
            if (!loop) break;
            cursor.* = 0;
        }

        const frames_to_copy = @min(frames_requested - frames_written, self.mFrameCount - cursor.*);
        const src = pcm_data[cursor.* * AUDIO_CHANNELS ..][0 .. frames_to_copy * AUDIO_CHANNELS];
        const dst = frames_out[frames_written * AUDIO_CHANNELS ..][0 .. frames_to_copy * AUDIO_CHANNELS];
        @memcpy(dst, src);

        cursor.* += frames_to_copy;
        frames_written += frames_to_copy;
    }

    return frames_written;
}
