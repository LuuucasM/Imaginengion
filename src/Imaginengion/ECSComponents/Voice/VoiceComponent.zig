const EngineContext = @import("../../Core/EngineContext.zig");
const ObjectRef = @import("../Entity/ObjectRefComponent.zig").Ref;
const AssetHandle = @import("../../ECSObjects/AssetHandle.zig");
const Bus = @import("../../ECSObjects/Bus.zig");
const Voice = @import("../../ECSObjects/Voice.zig");
const VoiceComponent = @This();

pub const Name: []const u8 = "VoiceComponent";

//what every voice has. How it should sound is a modifier read from somewhere else: an attached voice reads its
//source's AudioComponent live, a detached voice reads its own copies (VoiceAssetComponent, VolumeComponent, ...)

/// The object (entity, scene, player or game context) whose AudioComponent this voice plays, if it is attached. Its
/// AudioComponent is always there while this is set: the component clears it on its voices when it goes (see
/// AudioManager.OrphanVoices). Null for a detached voice, which does not care what happens to the object that started
/// it, and for an orphaned one
mSource: ?ObjectRef = null,
/// Was attached, and has lost its source (mSource is null). Fades out what it played last
mOrphaned: bool = false,

//the source component's other attached voices, a list starting at its mFirstVoice. NullObject at either end, and on a
//voice that is not attached

mNextVoice: Voice.Type = Voice.NullObject,
mPrevVoice: Voice.Type = Voice.NullObject,

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
