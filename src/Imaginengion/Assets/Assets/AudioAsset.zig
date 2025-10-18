const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;
const AudioBuffer = @import("AudioBuffers/AudioBuffer.zig");
const miniaudio = @import("../../Core/CImports.zig").miniaudio;
const AudioAsset = @This();

mAudioBuffer: AudioBuffer = undefined,

pub fn Init(allocator: std.mem.Allocator, _: []const u8, _: []const u8, asset_file: std.fs.File) !AudioAsset {
    return AudioAsset{
        .mAudioBuffer = try AudioBuffer.Init(allocator, asset_file),
    };
}

pub fn Deinit(self: *AudioAsset) !void {
    try self.mAudioBuffer.Deinit();
}

pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == AudioAsset) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

pub const Category: ComponentCategory = .Unique;
