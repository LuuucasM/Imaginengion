const BuiltinComponentCount = @import("../../ECS/Components.zig").BuiltinComponentCount;
const std = @import("std");
const AssetHandle = @import("../../ECSObjects/AssetHandle.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const ComponentsList = @import("../Components.zig").ComponentsList;
const AudioAsset = @import("../../Assets/Assets/AudioAsset.zig").AudioAsset;
const Assets = @import("../../Assets/Assets.zig");
const FileMetaData = Assets.FileMetaData;
const Entity = @import("../Entity.zig");
const EngineContext = @import("../../Core/EngineContext.zig");

const ImguiManager = @import("../../Imgui/Imgui.zig");

const AudioComponent = @This();

pub const PlaybackState = enum(u8) {
    Ready = 0,
    Playing = 1,
    Paused = 2,
    Finished = 3,
};

pub const AudioType = enum(u8) {
    Audio2D = 0,
    Audio3D = 1,
};

pub const Editable: bool = true;
pub const Name: []const u8 = "AudioComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == AudioComponent) {
            break :blk i + BuiltinComponentCount;
        }
    }
};

mParent: Entity.Type = Entity.NullEntity,
mFirst: Entity.Type = Entity.NullEntity,
mPrev: Entity.Type = Entity.NullEntity,
mNext: Entity.Type = Entity.NullEntity,

mAudioType: AudioType = .Audio2D,
mPlaybackState: PlaybackState = .Ready,
mAudioAsset: AssetHandle = .uninit,
mCursor: u64 = 0,
mVolume: f32 = 1.0,
mPitch: f32 = 1.0,
mLoop: bool = false,

pub fn ReadFrames(self: *AudioComponent, engine_context: EngineContext, frames_out: []f32, frame_count: u64) !u64 {
    const audio_asset = try self.mAudioAsset.GetAsset(engine_context, AudioAsset);

    return audio_asset.ReadFrames(frames_out, frame_count, *self.mCursor, self.mLoop);
}

pub fn Deinit(self: *AudioComponent, _: *EngineContext) !void {
    self.mAudioAsset.ReleaseAsset();
}

pub fn Clone(self: *const AudioComponent, _: *EngineContext) !AudioComponent {
    var new_component = self.*;

    // the copy releases the asset itself, so it needs its own reference
    new_component.mAudioAsset.RetainAsset();

    return new_component;
}
pub fn EditorRender(self: *AudioComponent, engine_context: *EngineContext) !void {
    // Volume drag
    _ = try ImguiManager.RenderFloatDrag(&self.mVolume, "Volume", 0.01, 0.0, 1.0);

    // Pitch drag
    _ = try ImguiManager.RenderFloatDrag(&self.mPitch, "Pitch", 0.01, 0.0, 0.0); //0.0 for upper bounds means no upper bounds i believe

    // Loop toggle
    try ImguiManager.RenderBool(&self.mLoop, "Looping?");

    try ImguiManager.RenderEnum(AudioType, &self.mAudioType, "Audio Type");

    try ImguiManager.ImguiSeparator();

    try ImguiManager.RenderAssetRef(engine_context, &self.mAudioAsset, "Audio Asset", "AudioAsset");
}

const Json = JsonUtils.JsonFields(AudioComponent, .{
    .AudioType = "mAudioType",
    .Audio = "mAudioAsset",
    .Volume = "mVolume",
    .Pitch = "mPitch",
    .Loop = "mLoop",
});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;
