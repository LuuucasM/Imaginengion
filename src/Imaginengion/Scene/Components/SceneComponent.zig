const std = @import("std");
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const EntityType = @import("../SceneManager.zig").EntityType;
const Entity = @import("../../GameObjects/Entity.zig");
const ECSManagerScenes = @import("../SceneManager.zig").ECSManagerScenes;
const FrameBuffer = @import("../../FrameBuffers/FrameBuffer.zig");
const GenUUID = @import("../../Core/UUID.zig").GenUUID;
const AssetHandle = @import("../../Assets/AssetHandle.zig");

const GameComponents = @import("../../GameObjects/Components.zig");
const IDComponent = GameComponents.IDComponent;
const SceneIDComponent = GameComponents.SceneIDComponent;
const NameComponent = GameComponents.NameComponent;
const TransformComponent = GameComponents.TransformComponent;
const CameraComponent = GameComponents.CameraComponent;

const SceneComponent = @This();

pub const LayerType = enum(u1) {
    GameLayer = 0,
    OverlayLayer = 1,
};

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == SceneComponent) {
            break :blk i;
        }
    }
};

mSceneAssetHandle: AssetHandle = .{ .mID = AssetHandle.NullHandle },
mLayerType: LayerType = undefined,
mFrameBuffer: FrameBuffer = undefined,
mECSManagerRef: *ECSManagerScenes = undefined,

pub fn Deinit(_: *SceneComponent) !void {}

pub fn CreateBlankEntity(self: *SceneComponent) !Entity {
    const new_entity = Entity{ .mEntityID = try self.mECSManagerRef.CreateEntity(), .mSceneLayerRef = self };
    try self.mEntityList.append(new_entity.mEntityID);
    try self.mEntitySet.put(new_entity.mEntityID, self.mEntityList.items.len - 1);

    return new_entity;
}

pub fn CreateEntity(self: *SceneComponent) !Entity {
    return self.CreateEntityWithUUID(try GenUUID());
}

pub fn CreateEntityWithUUID(self: *SceneComponent, uuid: u128) !Entity {
    const e = Entity{ .mEntityID = try self.mECSManagerRef.CreateEntity(), .mSceneLayerRef = self };
    try self.mEntityList.append(e.mEntityID);
    try self.mEntitySet.put(e.mEntityID, self.mEntityList.items.len - 1);
    _ = try e.AddComponent(IDComponent, .{ .ID = uuid });
    _ = try e.AddComponent(SceneIDComponent, .{ .SceneID = self.mUUID });
    var name = [_]u8{0} ** 24;
    @memcpy(name[0..14], "Unnamed Entity");
    _ = try e.AddComponent(NameComponent, .{ .Name = name });
    _ = try e.AddComponent(TransformComponent, null);

    return e;
}

pub fn DestroyEntity(self: SceneComponent, e: Entity) !void {
    try self.mECSManagerRef.DestroyEntity(e.mEntityID);
    const remove_loc = self.mEntitySet.get(e.mEntityID).?;
    const last_entity_id = self.mEntityList.items[self.mEntityList.items.len - 1];
    try self.mEntitySet.put(last_entity_id, remove_loc);
    self.mEntityList.swapRemove(remove_loc);
}

pub fn DuplicateEntity(self: *SceneComponent, original_entity: Entity) !Entity {
    const new_entity = Entity{ .mEntityID = try self.mECSManagerRef.DuplicateEntity(original_entity.mEntityID), .mSceneLayerRef = self };
    try self.mEntityList.append(new_entity.mEntityID);
    try self.mEntitySet.put(new_entity.mEntityID, self.mEntityList.items.len - 1);
    return new_entity;
}

pub fn OnViewportResize(self: *SceneComponent, width: usize, height: usize) !void {
    self.mFrameBuffer.Resize(width, height);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var camera_entities = try std.ArrayList(EntityType).initCapacity(allocator, self.mEntityList.items.len);
    try camera_entities.appendSlice(self.mEntityList.items);

    try self.mECSManagerRef.EntityListIntersection(&camera_entities, try self.mECSManagerRef.GetGroup(.{ .Component = CameraComponent }, allocator), allocator);

    for (camera_entities.items) |entity_id| {
        const camera_component = self.mECSManagerRef.GetComponent(CameraComponent, entity_id);
        if (camera_component.mIsFixedAspectRatio == false) {
            camera_component.SetViewportSize(width, height);
        }
    }
}

pub fn GetInd(self: SceneComponent) u32 {
    _ = self;
    return @intCast(Ind);
}

pub fn GetName(self: SceneComponent) []const u8 {
    _ = self;
    return "SceneComponent";
}
