const std = @import("std");
const UniformBuffer = @import("../UniformBuffers/UniformBuffer.zig");
const Window = @import("../Windows/Window.zig");

const RenderContext = @import("RenderContext.zig");
const Renderer2D = @import("Renderer2D.zig");
const Renderer3D = @import("Renderer3D.zig");

const AssetManager = @import("../Assets/AssetManager.zig");
const ShaderAsset = @import("../Assets/Assets.zig").ShaderAsset;

const SceneManager = @import("../Scene/SceneManager.zig");

const Entity = @import("../GameObjects/Entity.zig");
const EntityComponents = @import("../GameObjects/Components.zig");
const TransformComponent = EntityComponents.TransformComponent;
const QuadComponent = EntityComponents.QuadComponent;
const CameraComponent = EntityComponents.CameraComponent;
const EntityChildComponent = EntityComponents.ChildComponent;
const EntityParentComponent = EntityComponents.ParentComponent;

const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;

const Renderer = @This();

var RenderManager: Renderer = .{};

pub const RenderStats = struct {
    mQuadNum: usize = 0,
    mCircleNum: usize = 0,
    mLineNum: usize = 0,
};

const CameraData = extern struct {
    mPosition: [3]f32,
    _padding0: f32 = 0.0, // pad to 16 bytes
    mRotation: [4]f32,
    mPerspectiveFar: f32,
    _padding1: [3]f32 = .{ 0, 0, 0 }, // pad to 16 bytes (std140 rule)
};

const ResolutionData = extern struct {
    mWidth: f32,
    mHeight: f32,
};

mRenderContext: RenderContext = undefined,
mStats: RenderStats = .{},

mR2D: Renderer2D = undefined,
mR3D: Renderer3D = undefined,

mCameraBuffer: CameraData = std.mem.zeroes(CameraData),
mCameraUniformBuffer: UniformBuffer = undefined,

mResolutionBuffer: ResolutionData = std.mem.zeroes(ResolutionData),
mViewportResolutionUB: UniformBuffer = undefined,

var RenderAllocator = std.heap.DebugAllocator(.{}).init;

pub fn Init(window: *Window) !void {
    RenderManager.mRenderContext = RenderContext.Init(window);

    RenderManager.mR2D = try Renderer2D.Init(RenderAllocator.allocator());
    RenderManager.mR3D = Renderer3D.Init();

    RenderManager.mCameraUniformBuffer = UniformBuffer.Init(@sizeOf(CameraData));

    RenderManager.mViewportResolutionUB = UniformBuffer.Init(@sizeOf(ResolutionData));
}

pub fn Deinit() !void {
    try RenderManager.mR2D.Deinit();
    AssetManager.ReleaseAssetHandleRef(&RenderManager.mViewportShaderHandle);
    RenderManager.mCameraUniformBuffer.Deinit();
    RenderManager.mViewportResolutionUB.Deinit();

    RenderAllocator.deinit();
}

pub fn SwapBuffers() void {
    RenderManager.mRenderContext.SwapBuffers();
}

pub fn OnUpdate(scene_manager: *SceneManager, camera_component: *CameraComponent, camera_transform: *TransformComponent, frame_allocator: std.mem.Allocator) !void {
    BeginRendering(camera_component, camera_transform);

    //get all the shapes minus the children because we will render them with the parents
    const shapes_ids = try scene_manager.GetEntityGroup(GroupQuery{
        .Not = .{
            .mFirst = GroupQuery{ .Component = QuadComponent },
            .mSecond = GroupQuery{ .Component = EntityChildComponent },
        },
    }, frame_allocator);

    //TODO: sorting
    //TODO: culling
    try DrawShapes(shapes_ids, scene_manager);

    try EndRendering(camera_component);
}

pub fn GetRenderStats() RenderStats {
    return RenderManager.mStats;
}

fn BeginRendering(camera_component: *CameraComponent, camera_transform: *TransformComponent) void {
    RenderManager.mCameraBuffer.mPosition = [3]f32{ camera_transform.Translation[0], camera_transform.Translation[1], camera_transform.Translation[2] };
    RenderManager.mCameraBuffer.mRotation = [4]f32{ camera_transform.Rotation[0], camera_transform.Rotation[1], camera_transform.Rotation[2], camera_transform.Rotation[3] };
    RenderManager.mCameraBuffer.mPerspectiveFar = camera_component.mPerspectiveFar;
    RenderManager.mCameraUniformBuffer.SetData(&RenderManager.mCameraBuffer, @sizeOf(CameraData), 0);

    RenderManager.mResolutionBuffer.mWidth = @floatFromInt(camera_component.mViewportWidth);
    RenderManager.mResolutionBuffer.mHeight = @floatFromInt(camera_component.mViewportHeight);
    RenderManager.mViewportResolutionUB.SetData(&RenderManager.mResolutionBuffer, @sizeOf(ResolutionData), 0);

    RenderManager.mStats = std.mem.zeroes(RenderStats);

    RenderManager.mR2D.StartBatch();
}

fn DrawShapes(shapes: std.ArrayList(Entity.Type), scene_manager: *SceneManager) !void {
    for (shapes.items) |shape_entity_id| {
        const entity = scene_manager.GetEntity(shape_entity_id);

        DrawShape(entity);

        if (entity.HasComponent(EntityParentComponent)) {
            DrawChildren(entity);
        }
    }
}

fn DrawChildren(entity: Entity) void {}

fn DrawShape(entity: Entity) void {
    const transform_component = entity.GetComponent(TransformComponent);
    if (entity.HasComponent(QuadComponent)) {
        const quad_component = entity.GetComponent(QuadComponent);

        try RenderManager.mR2D.DrawQuad(
            transform_component,
            quad_component,
        );
    }
}

fn EndRendering(camera_component: *CameraComponent) !void {
    camera_component.mViewportFrameBuffer.Bind();
    defer camera_component.mViewportFrameBuffer.Unbind();

    const shader_asset = try camera_component.mViewportShaderHandle.GetAsset(ShaderAsset);
    shader_asset.mShader.Bind();

    try RenderManager.mR2D.SetBuffers();

    RenderManager.mCameraUniformBuffer.Bind(0);
    RenderManager.mViewportResolutionUB.Bind(1);

    RenderManager.mR2D.BindBuffers();

    RenderManager.mRenderContext.DrawIndexed(camera_component.mViewportVertexArray, camera_component.mViewportIndexBuffer.GetCount());
}
