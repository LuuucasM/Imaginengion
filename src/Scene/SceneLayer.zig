const std = @import("std");
const GenUUID = @import("../Core/UUID.zig").GenUUID;
const Entity = @import("../GameObjects/Entity.zig");
const ArraySet = @import("../Vendor/ziglang-set/src/array_hash_set/managed.zig").ArraySetManaged;
const ECSManager = @import("../ECS/ECSManager.zig");
const LinAlg = @import("../Math/LinAlg.zig");
const SceneLayer = @This();

const Components = @import("../GameObjects/Components.zig");
const IDComponent = Components.IDComponent;
const NameComponent = Components.NameComponent;
const TransformComponent = Components.TransformComponent;
const CameraComponent = Components.CameraComponent;

//.gscl
//.oscl
pub const LayerType = enum {
    GameLayer,
    OverlayLayer,
};

mName: std.ArrayList(u8),
mUUID: u128,
mPath: std.ArrayList(u8),
mLayerType: LayerType,
mInternalID: usize,
mECSManagerRef: *ECSManager,
mEntityIDs: ArraySet(u32),

pub fn Init(ECSAllocator: std.mem.Allocator, layer_type: LayerType, internal_id: usize, ecs_manager: *ECSManager) !SceneLayer {
    return SceneLayer{
        .mUUID = try GenUUID(),
        .mName = std.ArrayList(u8).init(ECSAllocator),
        .mPath = std.ArrayList(u8).init(ECSAllocator),
        .mLayerType = layer_type,
        .mInternalID = internal_id,
        .mECSManagerRef = ecs_manager,
        .mEntityIDs = ArraySet(u32).init(ECSAllocator),
    };
}

pub fn Deinit(self: *SceneLayer) void {
    self.mName.deinit();
    self.mPath.deinit();
    self.mEntityIDs.deinit();
}

pub fn CreateBlankEntity(self: *SceneLayer) !Entity {
    const new_entity = Entity{ .mEntityID = try self.mECSManagerRef.CreateEntity(), .mSceneLayerRef = self };
    _ = try self.mEntityIDs.add(new_entity.mEntityID);
    return new_entity;
}

pub fn CreateEntity(self: *SceneLayer) !Entity {
    return self.CreateEntityWithUUID(try GenUUID());
}
pub fn CreateEntityWithUUID(self: *SceneLayer, uuid: u128) !Entity {
    const e = Entity{ .mEntityID = try self.mECSManagerRef.CreateEntity(), .mSceneLayerRef = self };
    _ = try e.AddComponent(IDComponent, .{ .ID = uuid });
    var name = [_]u8{0} ** 24;
    @memcpy(name[0..14], "Unnamed Entity");
    _ = try e.AddComponent(NameComponent, .{ .Name = name });
    _ = try e.AddComponent(TransformComponent, null);

    _ = try self.mEntityIDs.add(e.mEntityID);

    return e;
}

pub fn DestroyEntity(self: SceneLayer, e: Entity) !void {
    try self.mECSManagerRef.DestroyEntity(e.mEntityID);
    self.mEntityIDs.remove(e.mEntityID);
}
pub fn DuplicateEntity(self: SceneLayer, original_entity: Entity) !Entity {
    const new_entity = Entity{ .mEntityID = try self.mECSManager.DuplicateEntity(original_entity.mEntityID), .mSceneLayerRef = &self };
    self.mEntityIDs.add(new_entity.mEntityID);
    return new_entity;
}

pub fn OnViewportResize(self: SceneLayer, width: usize, height: usize) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const entity_ids = try self.mECSManagerRef.GetGroup(&[_]type{CameraComponent}, allocator);
    var iter = entity_ids.iterator();
    while (iter.next()) |entry| {
        const entity_id = entry.key_ptr.*;
        const camera_component = self.mECSManagerRef.GetComponent(CameraComponent, entity_id);
        if (camera_component.mIsFixedAspectRatio == false) {
            camera_component.SetViewportSize(width, height);
        }
    }
}
