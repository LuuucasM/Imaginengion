const std = @import("std");
pub const Type = u32;
pub const ECSManagerPlayer = @import("../Scene/SceneManager.zig").ECSManagerPlayer;
pub const NullPlayer: Type = std.math.maxInt(Type);
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../GameObjects/Entity.zig");
const PlayerComponents = @import("Components.zig");
const PossessComponent = PlayerComponents.PossessComponent;
const Player = @This();

mEntityID: Type = NullPlayer,
mECSManagerRef: *ECSManagerPlayer = undefined,

pub fn AddComponent(self: Player, new_component: anytype) !*@TypeOf(new_component) {
    return try self.mECSManagerRef.AddComponent(self.mEntityID, new_component);
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
pub fn Delete(self: Player, engine_context: *EngineContext) !void {
    try engine_context.mGameEventManager.Insert(engine_context.EngineAllocator(), .{ .ET_DestroyEntityEvent = .{ .mEntity = self } });
    try engine_context.mImguiEventManager.Insert(engine_context.EngineAllocator(), .{ .ET_DeleteEntityEvent = .{ .mEntity = self } });
}
pub fn Possess(self: Player, entity: Entity) void {
    self.GetComponent(PossessComponent).?.mPossessedEntity = entity;
}
