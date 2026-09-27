const EngineContext = @import("../../Core/EngineContext.zig");
const VoiceFadeComponent = @This();

pub const Name: []const u8 = "VoiceFadeComponent";

//a voice with this is stopping: instead of being cut off, which clicks, it fades to silence over
//AudioManager.FADE_FRAMES and is destroyed once the fade is done. Added by StopVoice, and by the mix to a voice that
//has lost its source

/// How much of the fade is still to go. Counts down to 0 as the fade stage fades frames
mFramesLeft: u32 = 0,

pub fn Deinit(_: *VoiceFadeComponent, _: *EngineContext) void {}
