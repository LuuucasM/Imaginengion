const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const AudioManager = @import("../AudioManager/AudioManager.zig");
const ECSCore = @import("ECSObject.zig").Core;
const Voice = @This();

/// One playing sound: an AudioComponent's asset being played from some position. Made by AudioManager.PlayVoice,
/// and gone once it finishes or is stopped. Like an AssetHandle it points at its (engine level) manager directly,
/// not at a world, since voices from every world live in the one AudioManager
pub const Type = u32;
pub const NullObject: Type = std.math.maxInt(Type);

const Core = ECSCore(Voice);

pub const uninit: Voice = .{
    .mID = NullObject,
    .mManager = undefined,
};

mID: Type,
mManager: *AudioManager,

/// Stops the voice. It stays readable until the end of the frame, and is silent from the next update on
pub fn Stop(self: Voice, engine_context: *EngineContext) !void {
    try self.mManager.StopVoice(engine_context, self);
}

pub const GetComponent = Core.GetComponent;
pub const HasComponent = Core.HasComponent;
pub const IsActive = Core.IsActive;
pub const IsIDValid = Core.IsIDValid;
pub const Invalidate = Core.Invalidate;
