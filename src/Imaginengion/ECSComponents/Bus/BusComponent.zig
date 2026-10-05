const EngineContext = @import("../../Core/EngineContext.zig");
const Inspector = @import("../../UI/Inspector.zig");
const BusComponent = @This();

pub const Name: []const u8 = "BusComponent";

//what makes an AudioManager object a bus: a group that voices play into, mixed together and then turned up, down or
//paused as one. Buses form a tree through the ECS's parent/child links, rooted at the Master bus, and everything
//played through a bus also goes through every bus above it. Its volume is its VolumeComponent

/// A paused bus fades to silence, then holds every voice under it (in it or any bus below) where it is until unpaused
mPaused: bool = false,

/// The gain the bus is at right now. It moves toward the VolumeComponent's volume, or 0 while paused, at a fixed
/// speed (see AudioManager.FADE_FRAMES), so a volume change or a pause glides instead of clicking
mGain: f32 = 1.0,

pub fn Deinit(_: *BusComponent, _: *EngineContext) void {}

/// Only whether it is paused: its gain is where the mixer has got to, not a setting
pub fn UIRender(self: *BusComponent, ui: *Inspector.Builder) !void {
    try ui.Bool(&self.mPaused, "Paused", .{});
}
