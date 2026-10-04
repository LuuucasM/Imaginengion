const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const AudioManager = @import("../AudioManager/AudioManager.zig");
const VComponents = @import("../ECSComponents/VComponents.zig");
const BusComponent = VComponents.BusComponent;
const VolumeComponent = VComponents.VolumeComponent;
const ChildType = @import("../ECS/ECSManager.zig").ChildType;
const ECSCore = @import("ECSObject.zig").Core;
const Bus = @This();

/// A group that voices play into, which is turned up, down or paused as one (see BusComponent). Lives in the
/// AudioManager's ECS next to the voices and, like a Voice, points at the manager directly. Every AudioManager has a
/// Master bus at the root; the rest are made with CreateChild. The bus tree is saved with the project (see
/// AudioManager.SaveProjectSettings)
pub const Type = u32;
pub const NullObject: Type = std.math.maxInt(Type);

const Core = ECSCore(Bus);

/// Treated as the Master bus wherever a bus is looked up, e.g. an AudioComponent that has not picked one
pub const uninit: Bus = .{
    .mID = NullObject,
    .mManager = undefined,
};

/// Which of a bus's components it is made with. Its BusComponent is not optional, a bus always has one
pub const CreateConfig = struct {
    bAddUUID: bool,
    bAddName: bool,
    bAddVolume: bool,
};

pub const DefaultConfig: CreateConfig = .{
    .bAddUUID = true,
    .bAddName = true,
    .bAddVolume = true,
};

/// Nothing added, for a bus whose components all come from a file
pub const BlankConfig: CreateConfig = .{
    .bAddUUID = false,
    .bAddName = false,
    .bAddVolume = false,
};

mID: Type,
mManager: *AudioManager,

/// A new bus under this one. Buses only have bus children, so child_type is always .Entity; it is there so the
/// serializer can make children the same way for every object type
pub fn CreateChild(self: Bus, engine_context: *EngineContext, child_type: ChildType, config: CreateConfig) !Bus {
    std.debug.assert(child_type == .Entity);
    return try self.mManager.CreateBus(engine_context, self, config);
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

pub const AddComponent = Core.AddComponent;
pub const GetComponent = Core.GetComponent;
pub const HasComponent = Core.HasComponent;
pub const GetUUID = Core.GetUUID;
pub const GetName = Core.GetName;
pub const SetName = Core.SetName;
pub const GetIterator = Core.GetIterator;
pub const IsActive = Core.IsActive;
pub const IsIDValid = Core.IsIDValid;
pub const Invalidate = Core.Invalidate;
