const std = @import("std");
pub const Type = u32;
pub const ECSManagerPlayer = @import("../Scene/SceneManager.zig").ECSManagerPlayer;
pub const NullPlayer: Type = std.math.maxInt(Type);
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../GameObjects/Entity.zig");
const PlayerComponents = @import("Components.zig");
const PossessComponent = PlayerComponents.PossessComponent;
const PlayerNameComponent = PlayerComponents.NameComponent;
const FrameBuffer = @import("../FrameBuffers/FrameBuffer.zig");
const TextureFormat = @import("../FrameBuffers/InternalFrameBuffer.zig").TextureFormat;
const VertexArray = @import("../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const RenderTargetComponent = PlayerComponents.RenderTargetComponent;
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

pub fn GetName(self: Entity) []const u8 {
    return self.mSceneManager.mECSManagerGO.GetComponent(PlayerNameComponent, self.mEntityID).?.*.mName.items;
}

pub fn Duplicate(self: Player) !Player {
    return try self.mScenemanager.mECSManagerPL.DuplicateEntity(self.mEntityID);
}
pub fn Delete(self: Player, engine_context: *EngineContext) !void {
    self.mScenemanager.mECSManagerPL.DestroyEntity(engine_context.EngineAllocator(), self.mEntityID);
}
pub fn Possess(self: Player, entity: Entity) void {
    if (entity.GetComponent(PlayerSlotComponent)) |ps_component| {
        self.GetComponent(PossessComponent).?.mPossessedEntity = entity;
        ps_component.mPlayerEntity = self;
    } else {
        std.log.warn("Player {d} could not possess entity {d}", .{ self.mEntityID, entity.mEntityID });
    }
}

pub fn AddRenderTarget(self: Player, engine_context: *EngineContext) !*RenderTargetComponent {
    var new_render_comp = RenderTargetComponent{};
    const engine_allocator = engine_context.EngineAllocator();

    new_render_comp.mFrameBuffer = try FrameBuffer.Init(engine_allocator, &[_]TextureFormat{.RGBA8}, .None, 1, false, 1600, 900);
    new_render_comp.mVertexArray = VertexArray.Init();
    new_render_comp.mVertexBuffer = VertexBuffer.Init(@sizeOf([4][2]f32));
    new_render_comp.mIndexBuffer = undefined;

    const shader_asset = engine_context.mRenderer.GetSDFShader();
    try new_render_comp.mVertexBuffer.SetLayout(engine_context.EngineAllocator(), shader_asset.GetLayout());
    new_render_comp.mVertexBuffer.SetStride(shader_asset.GetStride());

    var index_buffer_data = [6]u32{ 0, 1, 2, 2, 3, 0 };
    new_render_comp.mIndexBuffer = IndexBuffer.Init(index_buffer_data[0..], 6);

    var data_vertex_buffer = [4][2]f32{ [2]f32{ -1.0, -1.0 }, [2]f32{ 1.0, -1.0 }, [2]f32{ 1.0, 1.0 }, [2]f32{ -1.0, 1.0 } };
    new_render_comp.mVertexBuffer.SetData(&data_vertex_buffer[0][0], @sizeOf([4][2]f32), 0);
    try new_render_comp.mVertexArray.AddVertexBuffer(engine_allocator, new_render_comp.mVertexBuffer);
    new_render_comp.mVertexArray.SetIndexBuffer(new_render_comp.mIndexBuffer);

    new_render_comp.SetViewportSize(1600, 900);
    return try self.AddComponent(engine_allocator, new_render_comp);
}

pub fn IsActive(self: Player) bool {
    return self.IsValidID() and self.mScenemanager.mECSManagerPL.IsActiveEntity(self.mEntityID);
}

pub fn IsValidID(self: Player) bool {
    return self.mEntityID != NullPlayer;
}
