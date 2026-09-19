const BuiltinComponentCount = @import("../../ECS/Components.zig").BuiltinComponentCount;
const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const AudioBuffer = @import("AudioBuffers/AudioBuffer.zig");
const miniaudio = @import("../../Core/CImports.zig").miniaudio;
const EngineContext = @import("../../Core/EngineContext.zig");
const AudioAsset = @This();

pub const Name: []const u8 = "AudioAsset";
pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == AudioAsset) {
            break :blk i + BuiltinComponentCount;
        }
    }
};

mAudioBuffer: AudioBuffer = .{},

pub fn Init(self: *AudioAsset, engine_context: *EngineContext, _: []const u8, rel_path: []const u8, asset_file: std.Io.File) !void {
    try self.mAudioBuffer.Init(engine_context, rel_path, asset_file);
}

pub fn Deinit(self: *AudioAsset, _: *EngineContext) !void {
    try self.mAudioBuffer.Deinit();
}
