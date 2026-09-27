const EngineContext = @import("../../Core/EngineContext.zig");
const VoicePitchComponent = @This();

pub const Name: []const u8 = "VoicePitchComponent";

/// The voice's own pitch, used instead of its source's AudioComponent's. A detached voice gets this since its source
/// may be gone before it finishes
mPitch: f32 = 1.0,

pub fn Deinit(_: *VoicePitchComponent, _: *EngineContext) void {}
