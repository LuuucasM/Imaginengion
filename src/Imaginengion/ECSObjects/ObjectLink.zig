//! A saved reference to another object: a handle, and the UUID it wants. The handle is empty (null), linked (live), or
//! waiting (neither) for an object that isn't loaded. A waiting reference saves the UUID it wants, so an object that isn't
//! loaded isn't lost, and links whenever an object with that UUID is loaded (WorldManager.RelinkRefs). A script's object
//! variables (ScriptValues) and components that point at an object (OverlayComponent, ...) all keep to this
const UUIDComponent = @import("../ECSComponents/Shared/UUIDComponent.zig");

/// A handle that is waiting for its object: not null, and no object's id
pub fn Waiting(comptime obj_t: type, world: anytype) obj_t {
    return .{ .mID = obj_t.NullObject - 1, .mManager = world };
}

/// What `object`, which wanted `wanted`, wants now, which is what it saves and what it wants after it is edited: its UUID
/// when live, what it wanted when waiting, and nothing when it is empty or points at something with no UUID, which could
/// not be found again
pub fn WantedNow(object: anytype, wanted: ?u64) ?u64 {
    if (object.mID == @TypeOf(object).NullObject) return null;
    if (!object.IsActive()) return wanted;
    const uuid = object.GetComponent(UUIDComponent) orelse return null;
    return uuid.ID;
}

/// Links `object` if it is waiting and what it wants is loaded. One that is empty stays empty and one that is linked stays
/// linked, so a value set by a script or in the editor is never replaced
pub fn Relink(object: anytype, wanted: ?u64) void {
    const obj_t = @TypeOf(object.*);
    if (object.mID == obj_t.NullObject or object.IsActive()) return;
    object.* = object.mManager.GetObjectByUUID(obj_t, wanted orelse return) orelse return;
}
