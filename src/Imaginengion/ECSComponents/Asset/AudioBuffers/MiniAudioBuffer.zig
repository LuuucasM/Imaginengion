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

/// Every decoded sample, interleaved AUDIO_CHANNELS per frame
pub fn GetSamples(self: MiniAudioBuffer) []const f32 {
    std.debug.assert(self.mPcmFrames != null);
    const pcm_data = @as([*]const f32, @ptrCast(@alignCast(self.mPcmFrames.?)));
    return pcm_data[0 .. self.mFrameCount * AUDIO_CHANNELS];
}
