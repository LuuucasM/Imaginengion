const std = @import("std");
const GenUUID = @import("../Core/UUID.zig").GenUUID;

const LinAlg = @import("../Math/LinAlg.zig");
const Mat4f32 = LinAlg.Mat4f32;

const ECSManagerScenes = @import("SceneManager.zig").ECSManagerScenes;
const Entity = @import("../GameObjects/Entity.zig");
const Components = @import("../GameObjects/Components.zig");
const ComponentsArray = Components.ComponentsList;

const RenderManager = @import("../Renderer/Renderer.zig");
const FrameBuffer = @import("../FrameBuffers/FrameBuffer.zig");
const InternalFrameBuffer = @import("../FrameBuffers/InternalFrameBuffer.zig").FrameBuffer;
const TextureFormat = @import("../FrameBuffers/InternalFrameBuffer.zig").TextureFormat;

const IDComponent = Components.IDComponent;
const SceneIDComponent = Components.SceneIDComponent;
const NameComponent = Components.NameComponent;
const TransformComponent = Components.TransformComponent;
const CameraComponent = Components.CameraComponent;

const SceneLayer = @This();

//.gscl
//.oscl

pub const LayerType = enum(u1) {
    GameLayer = 0,
    OverlayLayer = 1,
};

mName: std.ArrayList(u8),
mUUID: u128,
mPath: std.ArrayList(u8),
mEntityList: std.ArrayList(u32),
mEntitySet: std.AutoHashMap(u32, usize),
mLayerType: LayerType,
mInternalID: usize,
mFrameBuffer: FrameBuffer,
mECSManagerRef: *ECSManagerScenes,

pub fn Init(ECSAllocator: std.mem.Allocator, layer_type: LayerType, internal_id: usize, width: usize, height: usize, ecs_manager_ref: *ECSManagerScenes) !SceneLayer {
    return SceneLayer{
        .mUUID = try GenUUID(),
        .mName = std.ArrayList(u8).init(ECSAllocator),
        .mPath = std.ArrayList(u8).init(ECSAllocator),
        .mEntityList = std.ArrayList(u32).init(ECSAllocator),
        .mEntitySet = std.AutoHashMap(u32, usize).init(ECSAllocator),
        .mLayerType = layer_type,
        .mInternalID = internal_id,
        .mFrameBuffer = try FrameBuffer.Init(ECSAllocator, &[_]TextureFormat{.RGBA8}, .DEPTH24STENCIL8, 1, false, width, height),
        .mECSManagerRef = ecs_manager_ref,
    };
}

pub fn Deinit(self: *SceneLayer) void {
    self.mName.deinit();
    self.mPath.deinit();
    self.mEntityList.deinit();
    self.mEntitySet.deinit();
    self.mFrameBuffer.Deinit();
}

pub fn CreateBlankEntity(self: *SceneLayer) !Entity {
    const new_entity = Entity{ .mEntityID = try self.mECSManagerRef.CreateEntity(), .mSceneLayerRef = self };
    try self.mEntityList.append(new_entity.mEntityID);
    try self.mEntitySet.put(new_entity.mEntityID, self.mEntityList.items.len - 1);

    return new_entity;
}

pub fn CreateEntity(self: *SceneLayer) !Entity {
    return self.CreateEntityWithUUID(try GenUUID());
}
pub fn CreateEntityWithUUID(self: *SceneLayer, uuid: u128) !Entity {
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

pub fn DestroyEntity(self: SceneLayer, e: Entity) !void {
    try self.mECSManagerRef.DestroyEntity(e.mEntityID);
    const remove_loc = self.mEntitySet.get(e.mEntityID).?;
    const last_entity_id = self.mEntityList.items[self.mEntityList.items.len - 1];
    try self.mEntitySet.put(last_entity_id, remove_loc);
    self.mEntityList.swapRemove(remove_loc);
}

pub fn DuplicateEntity(self: *SceneLayer, original_entity: Entity) !Entity {
    const new_entity = Entity{ .mEntityID = try self.mECSManagerRef.DuplicateEntity(original_entity.mEntityID), .mSceneLayerRef = self };
    try self.mEntityList.append(new_entity.mEntityID);
    try self.mEntitySet.put(new_entity.mEntityID, self.mEntityList.items.len - 1);
    return new_entity;
}

pub fn OnViewportResize(self: *SceneLayer, width: usize, height: usize) !void {
    self.mFrameBuffer.Resize(width, height);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var camera_entities = try std.ArrayList(u32).initCapacity(allocator, self.mEntityList.items.len);
    try camera_entities.appendSlice(self.mEntityList.items);

    try self.mECSManagerRef.EntityListIntersection(&camera_entities, try self.mECSManagerRef.GetGroup(.{ .Component = CameraComponent }, allocator), allocator);

    for (camera_entities.items) |entity_id| {
        const camera_component = self.mECSManagerRef.GetComponent(CameraComponent, entity_id);
        if (camera_component.mIsFixedAspectRatio == false) {
            camera_component.SetViewportSize(width, height);
        }
    }
}
