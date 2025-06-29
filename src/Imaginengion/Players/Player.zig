const std = @import("std");
pub const Type = u32;
pub const ECSManagerPlayer = @import("PlayerManager.zig").ECSManagerPlayer;
pub const NullPlayer: Type = std.math.maxInt(Type);
const Player = @This();

mEntityID: Type,
mECSManagerRef: *ECSManagerPlayer,

pub fn AddComponent(self: Player, comptime component_type: type, component: ?component_type) !*component_type {
    return try self.mECSManagerRef.AddComponent(component_type, self.mEntityID, component);
}
pub fn RemoveComponent(self: Player, comptime component_type: type) !void {
    try self.mECSManagerRef.RemoveComponent(component_type, self.mEntityID);
}
pub fn GetComponent(self: Player, comptime component_type: type) *component_type {
    return self.mECSManagerRef.GetComponent(component_type, self.mEntityID);
}
pub fn HasComponent(self: Player, comptime component_type: type) bool {
    return self.mECSManagerRef.HasComponent(component_type, self.mEntityID);
}

pub fn Duplicate(self: Player) !Player {
    return try self.mECSManagerRef.DuplicateEntity(self.mEntityID);
}
