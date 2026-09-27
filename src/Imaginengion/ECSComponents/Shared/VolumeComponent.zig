const EngineContext = @import("../../Core/EngineContext.zig");
const VolumeComponent = @This();

pub const Name: []const u8 = "VolumeComponent";

/// How loud something in the AudioManager is, 0 silent to 1 full. On a bus it scales everything played through the
/// bus. On a detached voice it is the voice's own volume, used instead of its source's AudioComponent's, since its
/// source may be gone before it finishes
mVolume: f32 = 1.0,

pub fn Deinit(_: *VolumeComponent, _: *EngineContext) void {}
