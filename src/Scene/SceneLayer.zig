const std = @import("std");
const GenUUID = @import("../Core/UUID.zig").GenUUID;
const ArraySet = @import("../Vendor/ziglang-set/src/array_hash_set/managed.zig").ArraySetManaged;

const LinAlg = @import("../Math/LinAlg.zig");
const Mat4f32 = LinAlg.Mat4f32;

const ECSManager = @import("../ECS/ECSManager.zig");
const Entity = @import("..//GameObjects/Entity.zig");
const Components = @import("../GameObjects/Components.zig");
const ComponentsArray = Components.ComponentsList;

const RenderManager = @import("../Renderer/Renderer.zig");
const FrameBuffer = @import("../FrameBuffers/FrameBuffer.zig");
const InternalFrameBuffer = @import("../FrameBuffers/InternalFrameBuffer.zig").FrameBuffer;
const TextureFormat = @import("../FrameBuffers/InternalFrameBuffer.zig").TextureFormat;

const IDComponent = Components.IDComponent;
const NameComponent = Components.NameComponent;
const TransformComponent = Components.TransformComponent;
const CameraComponent = Components.CameraComponent;

const SceneLayer = @This();

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
mFrameBuffer: FrameBuffer,
mECSManagerRef: *ECSManager,

pub fn Init(ECSAllocator: std.mem.Allocator, layer_type: LayerType, internal_id: usize, width: usize, height: usize, ecs_manager_ref: *ECSManager) !SceneLayer {
    return SceneLayer{
        .mUUID = try GenUUID(),
        .mName = std.ArrayList(u8).init(ECSAllocator),
        .mPath = std.ArrayList(u8).init(ECSAllocator),
        .mLayerType = layer_type,
        .mInternalID = internal_id,
        .mFrameBuffer = try FrameBuffer.Init(ECSAllocator, InternalFrameBuffer(&[_]TextureFormat{.RGBA8}, .DEPTH24STENCIL8, 1, false), width, height),
        .mECSManagerRef = ecs_manager_ref,
    };
}

pub fn Deinit(self: *SceneLayer) void {
    self.mName.deinit();
    self.mPath.deinit();
    self.mFrameBuffer.Deinit();
}

pub fn CreateBlankEntity(self: *SceneLayer) !Entity {
    const new_entity = Entity{ .mEntityID = try self.mECSManagerRef.CreateEntity(), .mSceneLayerRef = self };

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

    return e;
}

pub fn DestroyEntity(self: SceneLayer, e: Entity) !void {
    try self.mECSManager.DestroyEntity(e.mEntityID);
}
pub fn DuplicateEntity(self: SceneLayer, original_entity: Entity) !Entity {
    const new_entity = Entity{ .mEntityID = try self.mECSManagerRef.DuplicateEntity(original_entity.mEntityID), .mSceneLayerRef = &self };

    return new_entity;
}

pub fn Render(self: SceneLayer, camera_projection: Mat4f32, camera_transform: Mat4f32) !void {
    self.mFrameBuffer.Bind();
    defer self.mFrameBuffer.Unbind();
    try RenderManager.RenderSceneLayer(self.mECSManagerRef, camera_projection, camera_transform);
}

pub fn OnViewportResize(self: *SceneLayer, width: usize, height: usize) !void {
    self.mFrameBuffer.Resize(width, height);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const entity_ids = try self.mECSManagerRef.GetQuery(.{ .Component = CameraComponent }, allocator);
    for (entity_ids.items) |entity_id| {
        const camera_component = self.mECSManagerRef.GetComponent(CameraComponent, entity_id);
        if (camera_component.mIsFixedAspectRatio == false) {
            camera_component.SetViewportSize(width, height);
        }
    }
}
