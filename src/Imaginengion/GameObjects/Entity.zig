const std = @import("std");
const ECSManagerGameObj = @import("../Scene/SceneManager.zig").ECSManagerGameObj;
const Components = @import("Components.zig");
const IDComponent = Components.IDComponent;
const NameComponent = Components.NameComponent;
const CameraComponent = Components.CameraComponent;
const EntityParentComponent = Components.ParentComponent;
const EntityChildComponent = Components.ChildComponent;
const PlayerSlotComponent = Components.PlayerSlotComponent;
const Tracy = @import("../Core/Tracy.zig");

pub const Type = u32;
pub const NullEntity: Type = std.math.maxInt(Type);
const Entity = @This();

mEntityID: Type,
mECSManagerRef: *ECSManagerGameObj,

pub fn AddComponent(self: Entity, comptime component_type: type, component: ?component_type) !*component_type {
    return try self.mECSManagerRef.AddComponent(component_type, self.mEntityID, component);
}
pub fn RemoveComponent(self: Entity, comptime component_type: type) !void {
    try self.mECSManagerRef.RemoveComponent(component_type, self.mEntityID);
}
pub fn GetComponent(self: Entity, comptime component_type: type) *component_type {
    return self.mECSManagerRef.GetComponent(component_type, self.mEntityID);
}
pub fn HasComponent(self: Entity, comptime component_type: type) bool {
    return self.mECSManagerRef.HasComponent(component_type, self.mEntityID);
}
pub fn GetUUID(self: Entity) u128 {
    return self.mECSManagerRef.GetComponent(IDComponent, self.mEntityID).*.ID;
}
pub fn GetName(self: Entity) []const u8 {
    return &self.mECSManagerRef.GetComponent(NameComponent, self.mEntityID).*.Name;
}
pub fn GetCameraEntity(self: Entity) ?Entity {
    const zone = Tracy.ZoneInit("Entity GetCameraEntity", @src());
    defer zone.Deinit();
    if (self.HasComponent(EntityParentComponent)) {
        const parent_component = self.GetComponent(EntityParentComponent);

        var curr_id = parent_component.mFirstChild;

        while (curr_id != Entity.NullEntity) {
            const child_entity = Entity{ .mEntityID = parent_component.mFirstChild, .mECSManagerRef = self.mECSManagerRef };

            if (child_entity.HasComponent(CameraComponent)) {
                return child_entity;
            }

            const child_component = child_entity.GetComponent(EntityChildComponent);
            curr_id = child_component.mNext;
        }
    }
    if (self.HasComponent(CameraComponent)) {
        return self;
    }
    return null;
}

pub fn Possessable(self: Entity) ?Entity {
    const zone = Tracy.ZoneInit("Entity Possessable", @src());
    defer zone.Deinit();

    if (self.HasComponent(EntityChildComponent)) {
        const child_component = self.GetComponent(EntityChildComponent);

        const parent_entity = Entity{ .mEntityID = child_component.mParent, .mECSManagerRef = self.mECSManagerRef };

        if (parent_entity.HasComponent(PlayerSlotComponent)) {
            return parent_entity;
        }
    }
    if (self.HasComponent(PlayerSlotComponent)) {
        return self;
    }
    return null;
}
pub fn Duplicate(self: Entity) !Entity {
    return try self.mECSManagerRef.DuplicateEntity(self.mEntityID);
}
