const std = @import("std");
pub const Type = u32;
pub const ECSManagerPlayer = @import("../Scene/SceneManager.zig").ECSManagerPlayer;
pub const NullPlayer: Type = std.math.maxInt(Type);
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../GameObjects/Entity.zig");
const PlayerComponents = @import("Components.zig");
const PossessComponent = PlayerComponents.PossessComponent;
const LensComponent = PlayerComponents.LensComponent;
const FrameBuffer = @import("../FrameBuffers/FrameBuffer.zig");
const TextureFormat = @import("../FrameBuffers/InternalFrameBuffer.zig").TextureFormat;
const VertexArray = @import("../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const IndexBuffer = @import("../IndexBuffers/IndexBuffer.zig");
const SceneManager = @import("../Scene/SceneManager.zig");
const EntityComponents = @import("../GameObjects/Components.zig");
const PlayerSlotComponent = EntityComponents.PlayerSlotComponent;
const Player = @This();

mEntityID: Type = NullPlayer,
mScenemanager: *SceneManager = undefined,

pub fn AddComponent(self: Player, engine_allocator: std.mem.Allocator, new_component: anytype) !*@TypeOf(new_component) {
    return try self.mScenemanager.mECSManagerPL.AddComponent(engine_allocator, self.mEntityID, new_component);
}
pub fn RemoveComponent(self: Player, comptime component_type: type) !void {
    try self.mScenemanager.mECSManagerPL.RemoveComponent(component_type, self.mEntityID);
}
pub fn GetComponent(self: Player, comptime component_type: type) ?*component_type {
    return self.mScenemanager.mECSManagerPL.GetComponent(component_type, self.mEntityID);
}
pub fn HasComponent(self: Player, comptime component_type: type) bool {
    return self.mScenemanager.mECSManagerPL.HasComponent(component_type, self.mEntityID);
}
pub fn Duplicate(self: Player) !Player {
    return try self.mScenemanager.mECSManagerPL.DuplicateEntity(self.mEntityID);
}
pub fn Delete(self: Player, engine_context: *EngineContext) !void {
    self.mScenemanager.mECSManagerPL.DestroyEntity(engine_context.EngineAllocator(), self.mEntityID);
}
pub fn Possess(self: Player, entity: Entity) void {
    if (entity.GetComponent(PlayerSlotComponent)) |ps_component| {
        self.GetComponent(PossessComponent).?.mPossessedEntity.mEntity = entity;
        ps_component.mPlayerEntity = self;
    } else {
        std.log.warn("Player {d} could not possess entity {d}", .{ self.mEntityID, entity.mEntityID });
    }
}

pub fn AddComponentLens(self: Player, engine_context: *EngineContext) !*LensComponent {
    var new_lens_component = LensComponent{};
    const engine_allocator = engine_context.EngineAllocator();

    new_lens_component.mFrameBuffer = try FrameBuffer.Init(engine_allocator, &[_]TextureFormat{.RGBA8}, .None, 1, false, 1600, 900);
    new_lens_component.mVertexArray = VertexArray.Init();
    new_lens_component.mVertexBuffer = VertexBuffer.Init(@sizeOf([4][2]f32));
    new_lens_component.mIndexBuffer = undefined;

    const shader_asset = engine_context.mRenderer.GetSDFShader();
    try new_lens_component.mVertexBuffer.SetLayout(engine_context.EngineAllocator(), shader_asset.GetLayout());
    new_lens_component.mVertexBuffer.SetStride(shader_asset.GetStride());

    var index_buffer_data = [6]u32{ 0, 1, 2, 2, 3, 0 };
    new_lens_component.mIndexBuffer = IndexBuffer.Init(index_buffer_data[0..], 6);

    var data_vertex_buffer = [4][2]f32{ [2]f32{ -1.0, -1.0 }, [2]f32{ 1.0, -1.0 }, [2]f32{ 1.0, 1.0 }, [2]f32{ -1.0, 1.0 } };
    new_lens_component.mVertexBuffer.SetData(&data_vertex_buffer[0][0], @sizeOf([4][2]f32), 0);
    try new_lens_component.mVertexArray.AddVertexBuffer(engine_allocator, new_lens_component.mVertexBuffer);
    new_lens_component.mVertexArray.SetIndexBuffer(new_lens_component.mIndexBuffer);

    new_lens_component.SetViewportSize(1600, 900);
    return try self.AddComponent(engine_allocator, new_lens_component);
}

pub fn IsActive(self: Player) bool {
    return self.IsValidID() and self.mScenemanager.mECSManagerPL.IsActiveEntity(self.mEntityID);
}

pub fn IsValidID(self: Player) bool {
    return self.mEntityID != NullPlayer;
}
