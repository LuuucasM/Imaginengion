const std = @import("std");
const AssetHandle = @import("../../ECSObjects/AssetHandle.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const Assets = @import("../AComponents.zig");
const FileMetaData = Assets.FileMetaData;
const Entity = @import("../../ECSObjects/Entity.zig");
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

mParent: Entity.Type = Entity.NullObject,
mFirst: Entity.Type = Entity.NullObject,
mPrev: Entity.Type = Entity.NullObject,
mNext: Entity.Type = Entity.NullObject,

mAudioType: AudioType = .Audio2D,
mPlaybackState: PlaybackState = .Ready,
mAudioAsset: AssetHandle = .uninit,
mCursor: u64 = 0,
mVolume: f32 = 1.0,
mPitch: f32 = 1.0,
mLoop: bool = false,

pub fn Deinit(self: *AudioComponent, _: *EngineContext) void {
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
