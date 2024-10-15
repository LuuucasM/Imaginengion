const LinAlg = @import("../Math/LinAlg.zig");
const ECSManager = @import("../ECS/ECSManager.zig");
const Entity = @import("../ECS/Entity.zig");
const GenUUID = @import("../Core/UUID.zig").GenUUID;

const Components = @import("../ECS/Components.zig");
const IDComponent = Components.IDComponent;
const SceneIDComponent = Components.SceneIDComponent;
const NameComponent = Components.NameComponent;
const TransformComponent = Components.TransformComponent;

const LayerType = SceneIDComponent.ELayerType;

const SceneLayerEditor = @This();

//.gscl
//.oscl

mUUID: u64,
mName: [24]u8,
mECSManager: *ECSManager,
mLayerType: LayerType,

pub fn CreateEntity(self: SceneLayerEditor, name: [24]u8) !Entity {
    return self.CreateEntityWithUUID(name, try GenUUID());
}
pub fn CreateEntityWithUUID(self: SceneLayerEditor, name: [24]u8, uuid: u64) !Entity {
    const e = Entity{ .mEntityID = try self.mECSManager.CreateEntity(), .mLayerType = self.mLayerType, .mLayer = self };
    _ = e.AddComponent(IDComponent, .{ .ID = uuid });
    _ = e.AddComponent(SceneIDComponent, .{ .ID = self.mUUID, .LayerType = self.mLayerType });
    _ = e.AddComponent(NameComponent, .{ .Name = name });
    _ = e.AddComponent(TransformComponent, .{ .Transform = LinAlg.InitMat4CompTime(1.0) });
    return e;
}

pub fn DestroyEntity(self: SceneLayerEditor, e: Entity) !void {
    try self.mECSManager.DestroyEntity(e.mEntityID);
}
pub fn DuplicateEntity(self: SceneLayerEditor, original_entity: Entity) Entity {
    return Entity{ .mEntityID = try self.mECSManager.DuplicateEntity(original_entity.mEntityID), .mLayerType = self.mLayerType, .mLayer = self };
}
