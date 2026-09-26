const std = @import("std");
const AssetHandle = @import("../../ECSObjects/AssetHandle.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const Assets = @import("../AComponents.zig");
const FileMetaData = Assets.FileMetaData;
const Entity = @import("../../ECSObjects/Entity.zig");
const EngineContext = @import("../../Core/EngineContext.zig");

const ImguiManager = @import("../../Imgui/Imgui.zig");

const AudioComponent = @This();

pub const AudioType = enum(u8) {
    Audio2D = 0,
    Audio3D = 1,
};

pub const Editable: bool = true;
pub const Name: []const u8 = "AudioComponent";

//how the sound should be played. The playing itself is done by voices in the AudioManager (see PlayVoice). Attached
//voices read these live, so one component can be playing any number of voices at once and editing it changes them all
mAudioType: AudioType = .Audio2D,
mAudioAsset: AssetHandle = .uninit,
mVolume: f32 = 1.0,
mPitch: f32 = 1.0,
mLoop: bool = false,

/// true: the voices this plays are attached. They read the settings above live and stop with the component (its
/// entity destroyed, it removed, or StopVoices). For sounds that belong to something: an engine hum, dialogue.
/// false: they are detached one-shots. They take a copy of the asset and volume when they start and play to the end
/// even if the entity is gone. For death screams, pickups, impacts. Can not loop, since nothing could stop them
mStopWithSource: bool = true,

/// Which batch of attached voices is this component's current one: a voice only plays while its token matches.
/// 0 until the component first plays. Not saved, and a copy starts at 0, so it can never match an older voice
mVoiceToken: u32 = 0,

/// Stops every attached voice this component started. They notice at the next mix, since their token no longer
/// matches. The next play hands the component a fresh token
pub fn StopVoices(self: *AudioComponent) void {
    self.mVoiceToken = 0;
}

pub fn Deinit(self: *AudioComponent, _: *EngineContext) void {
    self.mAudioAsset.ReleaseAsset();
}

pub fn Clone(self: *const AudioComponent, _: *EngineContext) !AudioComponent {
    var new_component = self.*;

    // the copy releases the asset itself, so it needs its own reference
    new_component.mAudioAsset.RetainAsset();

    //the original's voices are not the copy's: a re-copied world keeps its entity ids, so a copied token would let
    //old voices play from the copy
    new_component.mVoiceToken = 0;

    return new_component;
}
pub fn EditorRender(self: *AudioComponent, engine_context: *EngineContext) !void {
    // Volume drag
    _ = try ImguiManager.RenderFloatDrag(&self.mVolume, "Volume", 0.01, 0.0, 1.0);

    // Pitch drag
    _ = try ImguiManager.RenderFloatDrag(&self.mPitch, "Pitch", 0.01, 0.0, 0.0); //0.0 for upper bounds means no upper bounds i believe

    // Loop toggle
    try ImguiManager.RenderBool(&self.mLoop, "Looping?");

    try ImguiManager.RenderBool(&self.mStopWithSource, "Stop With Source?");

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
    .StopWithSource = "mStopWithSource",
});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;
