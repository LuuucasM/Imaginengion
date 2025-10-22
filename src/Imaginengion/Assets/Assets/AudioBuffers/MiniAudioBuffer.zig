const std = @import("std");
const ma = @import("../../../Core/CImports.zig").miniaudio;
const MiniAudioBuffer = @This();

const AUDIO_FORMAT = @import("../../../AudioManager/MiniAudioContext.zig").AUDIO_FORMAT;
const AUDIO_CHANNELS = @import("../../../AudioManager/MiniAudioContext.zig").AUDIO_CHANNELS;
const SAMPLE_RATE = @import("../../../AudioManager/MiniAudioContext.zig").SAMPLE_RATE;

mAudioConfig: ma.ma_audio_buffer_config = undefined,
mPcmFrames: ?*anyopaque = null,
mFrameCount: u64 = 0,

pub fn Init(self: *MiniAudioBuffer, asset_allocator: std.mem.Allocator, asset_file: std.fs.File) !void {
    _ = asset_allocator;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var file_data: std.ArrayList(u8) = .{};
    const file_size = try asset_file.getEndPos();
    try file_data.ensureTotalCapacity(arena_allocator, file_size);
    file_data.expandToCapacity();

    _ = try asset_file.readAll(file_data.items);

    var decoder_config = ma.ma_decoder_config_init(AUDIO_FORMAT, AUDIO_CHANNELS, SAMPLE_RATE);

    if (ma.ma_decode_memory(file_data.items.ptr, file_data.items.len, &decoder_config, &self.mFrameCount, &self.mPcmFrames) != ma.MA_SUCCESS) {
        return error.DecoderInitFail;
    }

    self.mAudioConfig = ma.ma_audio_buffer_config_init(AUDIO_FORMAT, AUDIO_CHANNELS, self.mFrameCount, self.mPcmFrames, null);
}

pub fn Deinit(self: *MiniAudioBuffer) !void {
    ma.ma_free(self.mPcmFrames, null);
}
