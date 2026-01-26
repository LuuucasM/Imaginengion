const std = @import("std");
const ECSManagerGameObj = @import("../Scene/SceneManager.zig").ECSManagerGameObj;
const Components = @import("Components.zig");
const IDComponent = Components.IDComponent;
const NameComponent = Components.NameComponent;
const CameraComponent = Components.CameraComponent;
const TransformComponent = Components.TransformComponent;
const EntityParentComponent = @import("../ECS/Components.zig").ParentComponent(Type);
const EntityChildComponent = @import("../ECS/Components.zig").ChildComponent(Type);
const PlayerSlotComponent = Components.PlayerSlotComponent;
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const LinAlg = @import("../Math/LinAlg.zig");
const Vec3f32 = LinAlg.Vec3f32;
const Quatf32 = LinAlg.Quatf32;
const ChildType = @import("../ECS/ECSManager.zig").ChildType;

pub const Type = u32;
pub const NullEntity: Type = std.math.maxInt(Type);
const Entity = @This();

mEntityID: Type = NullEntity,
mECSManagerRef: *ECSManagerGameObj = undefined,

pub fn AddComponent(self: Entity, comptime component_type: type, component: ?component_type) !*component_type {
    return try self.mECSManagerRef.AddComponent(component_type, self.mEntityID, component);
}
pub fn RemoveComponent(self: Entity, engine_allocator: std.mem.Allocator, comptime component_type: type) !void {
    self.mECSManagerRef.RemoveComponent(engine_allocator, component_type, self.mEntityID);
}
pub fn AddChild(self: Entity, child_type: ChildType) !Entity {
    return Entity{ .mEntityID = try self.mECSManagerRef.AddChild(self.mEntityID, child_type), .mECSManagerRef = self.mECSManagerRef };
}
pub fn GetComponent(self: Entity, comptime component_type: type) ?*component_type {
    return self.mECSManagerRef.GetComponent(component_type, self.mEntityID);
}
pub fn HasComponent(self: Entity, comptime component_type: type) bool {
    return self.mECSManagerRef.HasComponent(component_type, self.mEntityID);
}
pub fn GetUUID(self: Entity) u128 {
    return self.mECSManagerRef.GetComponent(IDComponent, self.mEntityID).?.*.ID;
}
pub fn GetName(self: Entity) []const u8 {
    return self.mECSManagerRef.GetComponent(NameComponent, self.mEntityID).?.*.mName.items;
}
pub fn GetCameraEntity(self: Entity) ?Entity {
    const zone = Tracy.ZoneInit("Entity GetCameraEntity", @src());
    defer zone.Deinit();
    if (self.GetComponent(EntityParentComponent)) |parent_component| {
        var curr_id = parent_component.mFirstEntity;

        while (true) : (if (curr_id == parent_component.mFirstEntity) break) {
            const child_entity = Entity{ .mEntityID = parent_component.mFirstEntity, .mECSManagerRef = self.mECSManagerRef };

            if (child_entity.HasComponent(CameraComponent)) {
                return child_entity;
            }

            const child_component = child_entity.GetComponent(EntityChildComponent).?;
            curr_id = child_component.mNext;
        }
    }
    if (self.HasComponent(CameraComponent)) {
        return self;
    }
    return null;
}

pub fn GetPossessable(self: Entity) ?Entity {
    const zone = Tracy.ZoneInit("Entity Possessable", @src());
    defer zone.Deinit();

    if (self.HasComponent(EntityChildComponent)) {
        const child_component = self.GetComponent(EntityChildComponent).?;

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
pub fn Delete(self: Entity, engine_context: *EngineContext) !void {
    try engine_context.mGameEventManager.Insert(engine_context.EngineAllocator(), .{ .ET_DestroyEntityEvent = .{ .mEntity = self } });
    try engine_context.mImguiEventManager.Insert(engine_context.EngineAllocator(), .{ .ET_DeleteEntityEvent = .{ .mEntity = self } });
}

pub fn _CalculateWorldTransform(self: Entity) void {
    const zone = Tracy.ZoneInit("Entity::_CalculateWorldTransform", @src());
    defer zone.Deinit();

    if (self.GetComponent(TransformComponent)) |transform| {
        var translation_out = transform.Translation;
        var rotation_out = transform.Rotation;
        var scale_out = transform.Scale;

        var child_component = self.GetComponent(EntityChildComponent);

        while (child_component != null) {
            const parent_entity = Entity{ .mEntityID = child_component.?.mParent, .mECSManagerRef = self.mECSManagerRef };

            if (parent_entity.GetComponent(TransformComponent)) |parent_transform| {
                translation_out += parent_transform.Translation;
                rotation_out = LinAlg.QuatMulQuat(rotation_out, parent_transform.Rotation);
                scale_out += parent_transform.Scale;
            }

            child_component = parent_entity.GetComponent(EntityChildComponent);
        }

        transform._InternalData.WorldPosition = translation_out;
        transform._InternalData.WorldRotation = rotation_out;
        transform._InternalData.WorldScale = scale_out;
    }
}
