const std = @import("std");
const GenUUID = @import("../Core/UUID.zig").GenUUID;
const LayerType = @import("../ECS/Components/SceneIDComponent.zig").ELayerType;
const Entity = @import("../ECS/Entity.zig");
const Set = @import("../Vendor/ziglang-set/src/array_hash_set/managed.zig").ArraySetManaged;
const ECSManager = @import("../ECS/ECSManager.zig");
const LinAlg = @import("../Math/LinAlg.zig");
const SceneLayer = @This();

const Components = @import("../ECS/Components.zig");
const IDComponent = Components.IDComponent;
const SceneIDComponent = Components.SceneIDComponent;
const NameComponent = Components.NameComponent;
const TransformComponent = Components.TransformComponent;

//.gscl
//.oscl

mName: std.ArrayList(u8),
mUUID: u128,
mPath: std.ArrayList(u8),
mLayerType: LayerType,
mInternalID: u8,
mECSManagerRef: *ECSManager,
mEntityIDs: Set(u32),

pub fn Init(ECSAllocator: std.mem.Allocator, layer_type: LayerType, internal_id: u8, ecs_manager: *ECSManager) !SceneLayer {
    return SceneLayer{
        .mUUID = try GenUUID(),
        .mName = std.ArrayList(u8).init(ECSAllocator),
        .mPath = std.ArrayList(u8).init(ECSAllocator),
        .mLayerType = layer_type,
        .mInternalID = internal_id,
        .mECSManagerRef = ecs_manager,
        .mEntityIDs = Set(u32).init(ECSAllocator),
    };
}

pub fn Deinit(self: *SceneLayer) void {
    self.mName.deinit();
    self.mPath.deinit();
    self.mEntityIDs.deinit();
}

pub fn CreateEntity(self: SceneLayer, name: [24]u8) !Entity {
    return self.CreateEntityWithUUID(name, GenUUID());
}
pub fn CreateEntityWithUUID(self: SceneLayer, name: [24]u8, uuid: u128) !Entity {
    const e = Entity{ .mEntityID = try self.mECSManager.CreateEntity(), .mSceneLayerRef = &self};
    _ = e.AddComponent(IDComponent, .{ .ID = uuid });
    _ = e.AddComponent(SceneIDComponent, .{ .ID = self.mUUID, .LayerType = self.mLayerType });
    _ = e.AddComponent(NameComponent, .{ .Name = name });
    _ = e.AddComponent(TransformComponent, .{ .Transform = LinAlg.InitMat4CompTime(1.0) });

    self.mEntityIDs.add(e.mEntityID);

    return e;
}

pub fn DestroyEntity(self: SceneLayer, e: Entity) !void {
    try self.mECSManagerRef.DestroyEntity(e.mEntityID);
    self.mEntityIDs.remove(e.mEntityID);
}
pub fn DuplicateEntity(self: SceneLayer, original_entity: Entity) !Entity {
    const new_entity = Entity{ .mEntityID = try self.mECSManager.DuplicateEntity(original_entity.mEntityID), .mSceneLayerRef = &self};
    self.mEntityIDs.add(new_entity.mEntityID);
    return new_entity;
}