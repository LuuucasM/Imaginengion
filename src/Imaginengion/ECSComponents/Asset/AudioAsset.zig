const std = @import("std");
const AssetsList = @import("../AComponents.zig").AssetsList;
const AudioBuffer = @import("AudioBuffers/AudioBuffer.zig");
const miniaudio = @import("../../Core/CImports.zig").miniaudio;
const EngineContext = @import("../../Core/EngineContext.zig");
const AudioAsset = @This();

pub const Name: []const u8 = "AudioAsset";

mAudioBuffer: AudioBuffer = .{},

pub fn Init(self: *AudioAsset, engine_context: *EngineContext, _: []const u8, rel_path: []const u8, asset_file: std.Io.File) !void {
    try self.mAudioBuffer.Init(engine_context, rel_path, asset_file);
}

pub fn Deinit(self: *AudioAsset, _: *EngineContext) void {
    self.mAudioBuffer.Deinit();
}
