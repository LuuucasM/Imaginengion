const EngineContext = @import("../../Core/EngineContext.zig");
const VoiceVolumeComponent = @This();

pub const Name: []const u8 = "VoiceVolumeComponent";

/// The voice's own volume, used instead of its source's AudioComponent's. A detached voice gets this since its source
/// may be gone before it finishes
mVolume: f32 = 1.0,

pub fn Deinit(_: *VoiceVolumeComponent, _: *EngineContext) void {}
