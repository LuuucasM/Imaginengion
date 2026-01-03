const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;
const AudioBuffer = @import("AudioBuffers/AudioBuffer.zig");
const miniaudio = @import("../../Core/CImports.zig").miniaudio;
const EngineContext = @import("../../Core/EngineContext.zig");
const AudioAsset = @This();

mAudioBuffer: AudioBuffer = .{},

pub fn Init(self: *AudioAsset, _: EngineContext, _: []const u8, _: []const u8, asset_file: std.fs.File) !void {
    try self.mAudioBuffer.Init(asset_file);
}

pub fn Deinit(self: *AudioAsset, _: EngineContext) !void {
    try self.mAudioBuffer.Deinit();
}

pub fn Setup(self: *AudioAsset) !void {
    try self.mAudioBuffer.Setup();
}

pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == AudioAsset) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

pub const Category: ComponentCategory = .Unique;
