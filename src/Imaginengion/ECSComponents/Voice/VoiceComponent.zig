const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const AssetHandle = @import("../../ECSObjects/AssetHandle.zig");
const Bus = @import("../../ECSObjects/Bus.zig");
const VoiceComponent = @This();

pub const Name: []const u8 = "VoiceComponent";

//what every voice has. How it should sound is a modifier read from somewhere else: an attached voice reads its
//source's AudioComponent live, a detached voice reads its own copies (VoiceAssetComponent, VolumeComponent, ...)

/// The entity whose AudioComponent this voice plays, if it is attached. Invalid for a detached voice, which does not
/// care what happens to the entity that started it
mSource: Entity = .uninit,
/// The source component's mVoiceToken when this voice started. An attached voice is orphaned once they differ
mToken: u32 = 0,

/// Frames into the asset this voice has played. Fractional, since a pitch other than 1 moves it by part of a frame
mCursor: f64 = 0.0,

//what the voice played in the last mix. An orphaned voice has lost its source, so it fades out on these instead, and
//a changed volume slides over from mLastVolume rather than jumping. Nothing here holds the asset: an orphaned voice
//only reads it for the few ms of its fade, and the asset manager keeps an asset around longer than that

/// The asset it read from
mAssetID: AssetHandle.Type = AssetHandle.NullObject,
/// The volume the last mix ended on
mLastVolume: f32 = 1.0,
/// The pitch it read at
mLastPitch: f32 = 1.0,
/// The bus it played into, or NullObject for Master. Set once for a detached voice, which keeps the bus its source
/// had when it started
mBusID: Bus.Type = Bus.NullObject,

pub fn Deinit(_: *VoiceComponent, _: *EngineContext) void {}
