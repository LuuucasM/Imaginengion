const LinAlg = @import("../Math/LinAlg.zig");
const ECSManager = @import("../ECS/ECSManager.zig");
const Entity = @import("../ECS/Entity.zig");
const GenUUID = @import("../Core/UUID.zig").GenUUID;

const Components = @import("../ECS/Components.zig");
const IDComponent = Components.IDComponent;
const SceneIDComponent = Components.SceneIDComponent;
const NameComponent = Components.NameComponent;
const TransformComponent = Components.TransformComponent;

const GameLayerEditor = @This();

mUUID: u64,
mName: [24]u8,
mECSManager: *ECSManager,

//pub fn Init
//pub fn Deinit

pub fn CreateEntity(self: GameLayerEditor, name: [24]u8) Entity {
    return self.CreateEntityWithUUID(name, GenUUID());
}
pub fn CreateEntityWithUUID(self: GameLayerEditor, name: [24]u8, uuid: u64) Entity {
    const e = Entity{ .mEntityID = self.mECSManager.CreateEntity() };
    _ = e.AddComponent(IDComponent, .{ .ID = uuid });
    _ = e.AddComponent(SceneIDComponent, .{ .ID = self.mUUID });
    _ = e.AddComponent(NameComponent, .{ .Name = name });
    _ = e.AddComponent(TransformComponent, .{ .Transform = LinAlg.InitMat4CompTime(1.0) });
    return e;
}

pub fn DestroyEntity(self: GameLayerEditor, e: Entity) !void {
    try self.mECSManager.DestroyEntity(e.mEntityID);
}
pub fn DuplicateEntity(self: GameLayerEditor, original_entity: Entity) Entity {
    return Entity{ .mEntityID = self.mECSManager.DuplicateEntity(original_entity.mEntityID) };
}
