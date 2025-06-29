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

pub fn OnUpdate(scene_manager: *SceneManager, camera_component: *CameraComponent, camera_transform: *TransformComponent) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    //Get all the players. then do the rendering for each player.
    BeginRendering(camera_component.mPerspectiveFar, camera_transform, scene_manager);

    //get all the shapes
    const shapes_ids = try scene_manager.GetEntityGroup(GroupQuery{ .Component = QuadComponent }, allocator);

    //TODO: sorting
    //TODO: culling
    try DrawShapes(shapes_ids, scene_manager);

    try EndRendering(scene_manager);
}

pub fn GetRenderStats() RenderStats {
    return RenderManager.mStats;
}

fn BeginRendering(perspective_far: f32, camera_transform: *TransformComponent, scene_manager: *SceneManager) void {
    RenderManager.mCameraBuffer.mPosition = [3]f32{ camera_transform.Translation[0], camera_transform.Translation[1], camera_transform.Translation[2] };
    RenderManager.mCameraBuffer.mRotation = [4]f32{ camera_transform.Rotation[0], camera_transform.Rotation[1], camera_transform.Rotation[2], camera_transform.Rotation[3] };
    RenderManager.mCameraBuffer.mPerspectiveFar = perspective_far;
    RenderManager.mCameraUniformBuffer.SetData(&RenderManager.mCameraBuffer, @sizeOf(CameraData), 0);

    RenderManager.mResolutionBuffer.mWidth = @floatFromInt(scene_manager.mViewportWidth);
    RenderManager.mResolutionBuffer.mHeight = @floatFromInt(scene_manager.mViewportHeight);
    RenderManager.mViewportResolutionUB.SetData(&RenderManager.mResolutionBuffer, @sizeOf(ResolutionData), 0);

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
    scene_manager.mViewportFrameBuffer.Bind();
    defer scene_manager.mViewportFrameBuffer.Unbind();
    scene_manager.mViewportFrameBuffer.ClearFrameBuffer(.{ 0.3, 0.3, 0.3, 1.0 });

    const shader_asset = try scene_manager.mViewportShaderHandle.GetAsset(ShaderAsset);
    shader_asset.mShader.Bind();

    try RenderManager.mR2D.SetBuffers();

    RenderManager.mCameraUniformBuffer.Bind(0);
    RenderManager.mViewportResolutionUB.Bind(1);

    RenderManager.mR2D.BindBuffers();

    RenderManager.mRenderContext.DrawIndexed(scene_manager.mViewportVertexArray, scene_manager.mViewportIndexBuffer.GetCount());
}
