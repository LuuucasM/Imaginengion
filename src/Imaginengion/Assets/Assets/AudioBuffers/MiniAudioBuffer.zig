const std = @import("std");
const ma = @import("../../../Core/CImports.zig").miniaudio;
const MiniAudioBuffer = @This();

const AUDIO_FORMAT = ma.ma_format_f32;
const AUDIO_CHANNELS = 2;
const SAMPLE_RATE = 44100;

mAudioBuffer: ma.ma_audio_buffer = undefined,

pub fn Init(asset_allocator: std.mem.Allocator, asset_file: std.fs.File) !MiniAudioBuffer {
    _ = asset_allocator;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var file_data: std.ArrayList(u8) = .{};
    const file_size = try asset_file.getEndPos();
    try file_data.ensureTotalCapacity(arena_allocator, file_size);
    file_data.expandToCapacity();

    _ = try asset_file.readAll(file_data.items);

    std.debug.print("do i make it this far 1\n", .{});

    var decoder_config = ma.ma_decoder_config_init(AUDIO_FORMAT, AUDIO_CHANNELS, SAMPLE_RATE);
    var frame_count: u64 = 0;
    var pcm_frames: ?*anyopaque = null;

    std.debug.print("do i make it this far 2\n", .{});

    const decoder_result = ma.ma_decode_memory(file_data.items.ptr, file_data.items.len, &decoder_config, &frame_count, &pcm_frames);
    if (decoder_result == ma.MA_ERROR) return error.DecoderInitFail;

    std.debug.print("do i make it this far 3\n", .{});

    var miniaudio_buffer: MiniAudioBuffer = .{};
    const audio_buffer_config = ma.ma_audio_buffer_config_init(AUDIO_FORMAT, AUDIO_CHANNELS, frame_count, pcm_frames, null);

    std.debug.print("do i make it this far 4\n", .{});

    const buffer_result = ma.ma_audio_buffer_init(&audio_buffer_config, &miniaudio_buffer.mAudioBuffer);
    if (buffer_result == ma.MA_ERROR) return error.AudioBufferInitFail;

    std.debug.print("doi make ti this far 5\n", .{});

    return miniaudio_buffer;
}

pub fn Deinit(self: *MiniAudioBuffer) !void {
    ma.ma_audio_buffer_uninit(&self.mAudioBuffer);
}
