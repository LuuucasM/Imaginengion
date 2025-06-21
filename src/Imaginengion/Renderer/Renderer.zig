const std = @import("std");
const builtin = @import("builtin");
const ArraySet = @import("../Vendor/ziglang-set/src/array_hash_set/managed.zig").ArraySetManaged;
const UniformBuffer = @import("../UniformBuffers/UniformBuffer.zig");
const VertexArray = @import("../VertexArrays/VertexArray.zig");
const FrameBuffer = @import("../FrameBuffers/FrameBuffer.zig");
const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const IndexBuffer = @import("../IndexBuffers/IndexBuffer.zig");
const Window = @import("../Windows/Window.zig");

const RenderContext = @import("RenderContext.zig");
const Renderer2D = @import("Renderer2D.zig");
const Renderer3D = @import("Renderer3D.zig");

const AssetManager = @import("../Assets/AssetManager.zig");
const AssetHandle = @import("../Assets/AssetHandle.zig");
const Assets = @import("../Assets/Assets.zig");
const Texture2D = Assets.Texture2D;
const ShaderAsset = Assets.ShaderAsset;

const LinAlg = @import("../Math/LinAlg.zig");
const Vec2f32 = LinAlg.Vec2f32;
const Vec3f32 = LinAlg.Vec3f32;
const Vec4f32 = LinAlg.Vec4f32;
const Mat4f32 = LinAlg.Mat4f32;

const SceneManager = @import("../Scene/SceneManager.zig");
const SceneType = SceneManager.SceneType;
const ECSManagerScenes = SceneManager.ECSManagerScenes;
const SceneLayer = @import("../Scene/SceneLayer.zig");
const ComponentManager = @import("../ECS/ComponentManager.zig");

const Entity = @import("../GameObjects/Entity.zig");
const EntityComponents = @import("../GameObjects/Components.zig");
const TransformComponent = EntityComponents.TransformComponent;
const EntitySceneComponent = EntityComponents.SceneIDComponent;
const QuadComponent = EntityComponents.QuadComponent;
const SpriteRenderComponent = EntityComponents.SpriteRenderComponent;
const CircleRenderComponent = EntityComponents.CircleRenderComponent;
const CameraComponent = EntityComponents.CameraComponent;
const EntityChildComponent = EntityComponents.ChildComponent;

const SceneComponents = @import("../Scene/SceneComponents.zig");
const StackPosComponent = SceneComponents.StackPosComponent;
const SceneComponent = SceneComponents.SceneComponent;

const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;

const TextureFormat = @import("../FrameBuffers/InternalFrameBuffer.zig").TextureFormat;

const Renderer = @This();

var RenderManager: Renderer = .{};

pub const RenderStats = struct {
    mQuadNum: usize = 0,
    mCircleNum: usize = 0,
    mLineNum: usize = 0,
};

const CameraData = extern struct {
    mPosition: [3]f32,
    mRotation: [4]f32,
    mPerspectiveFar: f32,
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

    RenderManager.mViewportResolutionUB = UniformBuffer.Init(@sizeOf([2]f32));
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

pub fn OnUpdate(scene_manager: *SceneManager, camera_component: *CameraComponent, camera_transform: *TransformComponent) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    std.log.debug("begin rendering\n", .{});
    BeginRendering(camera_component.mPerspectiveFar, camera_transform);

    //get all the shapes
    const shapes_ids = try scene_manager.GetEntityGroup(GroupQuery{ .Component = QuadComponent }, allocator);

    //TODO: sorting
    //TODO: culling
    std.log.debug("draw shapes\n", .{});
    try DrawShapes(shapes_ids, scene_manager);

    std.log.debug("end rendering\n", .{});
    try EndRendering(scene_manager);
    std.log.debug("end on update\n", .{});
}

pub fn GetRenderStats() RenderStats {
    return RenderManager.mStats;
}

fn BeginRendering(perspective_far: f32, camera_transform: *TransformComponent) void {
    RenderManager.mCameraBuffer.mPosition = camera_transform.Translation;
    RenderManager.mCameraBuffer.mRotation = camera_transform.Rotation;
    RenderManager.mCameraBuffer.mPerspectiveFar = perspective_far;
    RenderManager.mCameraUniformBuffer.SetData(&RenderManager.mCameraBuffer, @sizeOf(CameraData), 0);

    RenderManager.mStats = std.mem.zeroes(RenderStats);

    RenderManager.mR2D.StartBatch();
}

fn DrawShapes(shapes: std.ArrayList(Entity.Type), scene_manager: *SceneManager) !void {
    for (shapes.items) |shape_entity_id| {
        const entity = scene_manager.GetEntity(shape_entity_id);
        const transform_component = entity.GetComponent(TransformComponent);

        if (entity.HasComponent(QuadComponent)) {
            const quad_component = entity.GetComponent(QuadComponent);

            try RenderManager.mR2D.DrawQuad(
                transform_component,
                quad_component,
            );
        }
        //else if has circle, line, other shapes
    }
}

fn EndRendering(scene_manager: *SceneManager) !void {
    std.log.debug("scene spec list\n", .{});
    scene_manager.mViewportFrameBuffer.Bind();
    defer scene_manager.mViewportFrameBuffer.Unbind();
    scene_manager.mViewportFrameBuffer.ClearFrameBuffer(.{ 0.3, 0.3, 0.3, 1.0 });

    std.log.debug("shader asset\n", .{});
    const shader_asset = try scene_manager.mViewportShaderHandle.GetAsset(ShaderAsset);
    shader_asset.mShader.Bind();

    std.log.debug("set buffers\n", .{});
    RenderManager.mR2D.SetBuffers();

    std.log.debug("canmera uniform\n", .{});
    RenderManager.mCameraUniformBuffer.Bind(0);
    std.log.debug("ivewport resolution\n", .{});
    RenderManager.mViewportResolutionUB.Bind(1);

    std.log.debug("bind buffers\n", .{});
    RenderManager.mR2D.BindBuffers();

    std.log.debug("va\n", .{});
    const va = scene_manager.mViewportVertexArray;
    std.log.debug("ib\n", .{});
    const ib = scene_manager.mViewportIndexBuffer;
    std.log.debug("count\n", .{});
    const count = ib.GetCount();

    std.log.debug("draw indexed\n", .{});
    RenderManager.mRenderContext.DrawIndexed(va, count);
    std.log.debug("after draw indexed\n", .{});
}
