const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const AudioManager = @import("../AudioManager/AudioManager.zig");
const VComponents = @import("../ECSComponents/VComponents.zig");
const BusComponent = VComponents.BusComponent;
const VolumeComponent = VComponents.VolumeComponent;
const ECSCore = @import("ECSObject.zig").Core;
const Bus = @This();

/// A group that voices play into, which is turned up, down or paused as one (see BusComponent). Lives in the
/// AudioManager's ECS next to the voices and, like a Voice, points at the manager directly. Every AudioManager has a
/// Master bus at the root; the rest are made with CreateChild
pub const Type = u32;
pub const NullObject: Type = std.math.maxInt(Type);

const Core = ECSCore(Bus);

/// Treated as the Master bus wherever a bus is looked up, e.g. an AudioComponent that has not picked one
pub const uninit: Bus = .{
    .mID = NullObject,
    .mManager = undefined,
};

mID: Type,
mManager: *AudioManager,

/// A new bus under this one, at full volume
pub fn CreateChild(self: Bus, engine_context: *EngineContext) !Bus {
    return try self.mManager.CreateBus(engine_context, self);
}

/// Deletes this bus and every bus under it at the end of the frame. Voices playing through them move to Master.
/// The Master bus can not be deleted
pub fn Delete(self: Bus, engine_context: *EngineContext) !void {
    try self.mManager.DeleteBus(engine_context, self);
}

pub fn SetVolume(self: Bus, volume: f32) void {
    if (self.GetComponent(VolumeComponent)) |volume_component| volume_component.mVolume = volume;
}

/// Pausing fades everything under the bus out, then holds it where it is. Unpausing fades it back in from there
pub fn SetPaused(self: Bus, paused: bool) void {
    if (self.GetComponent(BusComponent)) |bus_component| bus_component.mPaused = paused;
}

pub const GetComponent = Core.GetComponent;
pub const HasComponent = Core.HasComponent;
pub const GetName = Core.GetName;
pub const GetIterator = Core.GetIterator;
pub const IsActive = Core.IsActive;
pub const IsIDValid = Core.IsIDValid;
pub const Invalidate = Core.Invalidate;
