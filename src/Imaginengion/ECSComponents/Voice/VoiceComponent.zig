const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const VoiceComponent = @This();

pub const Name: []const u8 = "VoiceComponent";

//what every voice has. How it should sound is a modifier read from somewhere else: an attached voice reads its
//source's AudioComponent live, a detached voice reads its own copies (VoiceAssetComponent, VoiceVolumeComponent)

/// The entity whose AudioComponent this voice plays, if it is attached. Invalid for a detached voice, which does not
/// care what happens to the entity that started it
mSource: Entity = .uninit,
/// The source component's mVoiceToken when this voice started. An attached voice dies once they differ
mToken: u32 = 0,

/// Set by StopVoice, so a stopped voice is silent from the next mix on even though it is only destroyed at the end
/// of the frame
mStopped: bool = false,

/// Frames into the asset this voice has played
mCursor: u64 = 0,

pub fn Deinit(_: *VoiceComponent, _: *EngineContext) void {}
