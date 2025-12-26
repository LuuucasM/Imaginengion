const AssetHandle = @import("../../Assets/AssetHandle.zig");
const AssetManager = @import("../../Assets/AssetManager.zig");
const ComponentsList = @import("../Components.zig").ComponentsList;
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;
const AudioAsset = @import("../../Assets/Assets/AudioAsset.zig").AudioAsset;
const AudioComponent = @This();

pub const PlaybackState = enum(u8) {
    Ready = 0,
    Playing = 0,
    Paused = 1,
    Finished = 2,
    Virtualized = 3,
};

pub const AudioType = enum(u8) {
    Audio2D = 0,
    Audio3D = 1,
};

pub const Category: ComponentCategory = .Unique;
pub const Editable: bool = true;

mAudioType: AudioType = .Audio2D,
mPlaybackState: PlaybackState = .Ready,
mAudioAsset: AssetHandle = .{},
mCursor: u64 = 0,
mVolume: f32 = 1.0,
mPitch: f32 = 1.0,
mLoop: bool = false,

pub fn ReadFrames(self: *AudioComponent, frames_out: []f32, frame_count: u64) !u64 {
    const audio_asset = try self.mAudioAsset.GetAsset(AudioAsset);

    audio_asset.ReadFrames(frames_out, frame_count, *self.mCursor, self.mLoop);
}

pub fn Deinit(self: *AudioComponent) void {
    if (self.mAudioBuffer.mID != AssetHandle.NullHandle) {
        AssetManager.ReleaseAssetHandleRef(&self.mAudioBuffer);
    }
}

pub fn GetName(_: AudioComponent) []const u8 {
    return "AudioComponent";
}

pub fn GetInd(_: AudioComponent) u32 {
    return @intCast(Ind);
}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == AudioComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};
