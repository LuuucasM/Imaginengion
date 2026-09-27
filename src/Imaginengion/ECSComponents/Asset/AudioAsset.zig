const std = @import("std");
const AssetsList = @import("../AComponents.zig").AssetsList;
const AudioBuffer = @import("AudioBuffers/AudioBuffer.zig");
const miniaudio = @import("../../Core/CImports.zig").miniaudio;
const EngineContext = @import("../../Core/EngineContext.zig");
const AudioAsset = @This();

pub const Name: []const u8 = "AudioAsset";

/// Only the decoded sound. Playback position and state belong to whoever is playing it (a voice in the
/// AudioManager), so one asset can be played by any number of voices at once
mAudioBuffer: AudioBuffer = .{},

pub fn Init(self: *AudioAsset, engine_context: *EngineContext, _: []const u8, rel_path: []const u8, asset_file: std.Io.File) !void {
    try self.mAudioBuffer.Init(engine_context, rel_path, asset_file);
}

pub fn Deinit(self: *AudioAsset, _: *EngineContext) void {
    self.mAudioBuffer.Deinit();
}

pub fn GetFrameCount(self: AudioAsset) u64 {
    return self.mAudioBuffer.GetFrameCount();
}

/// Every decoded sample, interleaved AUDIO_CHANNELS per frame. The asset can be reloaded between frames, so callers
/// hold a handle and fetch the asset (and these samples) each time instead of keeping them
pub fn GetSamples(self: AudioAsset) []const f32 {
    return self.mAudioBuffer.GetSamples();
}
