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

pub const RenderStats = struct {
    mQuadNum: usize = 0,
    mCircleNum: usize = 0,
    mLineNum: usize = 0,
};

const CameraBuffer = extern struct {
    mBuffer: [4][4]f32,
};

mRenderContext: RenderContext = undefined,
mStats: RenderStats = .{},

mR2D: Renderer2D = undefined,
mR3D: Renderer3D = undefined,

mTexturesMap: std.AutoHashMap(usize, usize) = undefined,
mTextures: std.ArrayList(AssetHandle) = undefined,

mCameraBuffer: CameraBuffer = std.mem.zeroes(CameraBuffer),
mCameraUniformBuffer: UniformBuffer = undefined,

mViewportFrameBuffer: FrameBuffer,
mViewportWidth: usize,
mViewportHeight: usize,
mViewportVertexArray: VertexArray,
mViewportVertexBuffer: VertexBuffer,
mViewportIndexBuffer: IndexBuffer,
mViewportShaderHandle: AssetHandle,

var RenderAllocator = std.heap.DebugAllocator(.{}).init;

pub fn Init(window: *Window) !Renderer {
    const new_render_context = RenderContext.Init(window);

    var new_renderer = Renderer{
        .mRenderContext = new_render_context,
        .mR2D = try Renderer2D.Init(RenderAllocator.allocator()),
        .mR3D = Renderer3D.Init(),
        .mTexturesMap = std.AutoHashMap(usize, usize).init(RenderAllocator.allocator()),
        .mTextures = try std.ArrayList(AssetHandle).initCapacity(RenderAllocator.allocator(), new_render_context.GetMaxTextureImageSlots()),
        .mCameraUniformBuffer = UniformBuffer.Init(@sizeOf(CameraBuffer)),
        .mViewportFrameBuffer = try FrameBuffer.Init(RenderAllocator.allocator(), &[_]TextureFormat{.RGBA8}, .None, 1, false, window.GetWidth(), window.GetHeight()),
        .mViewportHeight = window.GetHeight(),
        .mViewportWidth = window.GetWidth(),
        .mViewportVertexArray = VertexArray.Init(RenderAllocator.allocator()),
        .mViewportVertexBuffer = VertexBuffer.Init(RenderAllocator.allocator(), 4 * @sizeOf(Vec2f32)),
        .mViewportIndexBuffer = undefined,
        .mViewportShaderHandle = try AssetManager.GetAssetHandleRef("assets/shaders/SDFShader.glsl", .Eng),
    };

    //TODO: FINISH SETTING UP THE NEW SHADER STUFF INTRODUCED INTO THE RENDERER
    try new_renderer.mTexturesMap.ensureTotalCapacity(@intCast(new_renderer.mRenderContext.GetMaxTextureImageSlots()));

    var data_index_buffer = [6]u32{ 0, 1, 2, 2, 3, 0 };
    new_renderer.mViewportIndexBuffer = IndexBuffer.Init(&data_index_buffer, 6 * @sizeOf(u32));

    const shader_asset = try new_renderer.mViewportShaderHandle.GetAsset(ShaderAsset);
    new_renderer.mViewportVertexBuffer.SetLayout(shader_asset.mShader.GetLayout());
    new_renderer.mViewportVertexBuffer.SetStride(shader_asset.mShader.GetStride());

    var data_vertex_buffer = [4][2]f32{ f32{ -1.0, -1.0 }, f32{ 1.0, -1.0 }, f32{ 1.0, 1.0 }, f32{ -1.0, 1.0 } };
    new_renderer.mViewportVertexBuffer.SetData(&data_vertex_buffer[0], @sizeOf([4][2]f32));

    new_renderer.mViewportVertexArray.AddVertexBuffer(new_renderer.mViewportVertexBuffer);

    new_renderer.mViewportVertexArray.SetIndexBuffer(new_renderer.mViewportIndexBuffer);

    return new_renderer;
}

pub fn Deinit(self: *Renderer) !void {
    AssetManager.ReleaseAssetHandleRef(&self.mViewportShaderHandle);
    self.mViewportVertexBuffer.Deinit();
    self.mViewportIndexBuffer.Deinit();
    self.mViewportVertexArray.Deinit();
    self.mViewportFrameBuffer.Deinit();

    try self.mR2D.Deinit();
    self.mTexturesMap.deinit();
    self.mTextures.deinit();
}

pub fn SwapBuffers(self: Renderer) void {
    self.mRenderContext.SwapBuffers();
}

pub fn OnUpdate(self: *Renderer, scene_manager: *SceneManager, camera_component: *CameraComponent, camera_transform: *TransformComponent) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const camera_view_projection = LinAlg.Mat4MulMat4(camera_component.mProjection, LinAlg.Mat4Inverse(camera_transform.GetTransformMatrix()));

    self.BeginRendering(camera_view_projection);

    self.StartBatch();

    //get all the shapes
    const shapes_ids = try scene_manager.GetEntityGroup(GroupQuery{ .Component = QuadComponent }, allocator);

    //TODO: sorting
    //TODO: culling

    try self.DrawShapes(shapes_ids, scene_manager);

    try self.FinishBatch();
}

pub fn GetRenderStats(self: Renderer) RenderStats {
    return self.mStats;
}

fn BeginRendering(self: *Renderer, camera_viewprojection: Mat4f32) void {
    self.mCameraBuffer.mBuffer = LinAlg.Mat4ToArray(camera_viewprojection);
    self.mCameraUniformBuffer.SetData(&self.mCameraBuffer, @sizeOf(CameraBuffer), 0);

    self.mStats = std.mem.zeroes(RenderStats);

    self.mR2D.StartBatch();
}

fn DrawShapes(self: *Renderer, shapes: std.ArrayList(Entity.Type), scene_manager: *SceneManager) !void {
    for (shapes.items) |shape_entity_id| {
        const entity = scene_manager.GetEntity(shape_entity_id);
        const transform_component = entity.GetComponent(TransformComponent);

        if (entity.HasComponent(QuadComponent)) {
            const quad_component = entity.GetComponent(QuadComponent);

            try self.mR2D.DrawQuad(
                transform_component.WorldTransform,
                quad_component,
            );
        }
        //else if has circle, line, other shapes
    }
}

fn FinishBatch(self: *Renderer) !void {
    self.mViewportFrameBuffer.Bind();
    defer self.mViewportFrameBuffer.Unbind();
    self.mViewportFrameBuffer.ClearFrameBuffer(.{ 0.3, 0.3, 0.3, 1.0 });

    const shader_asset = try self.mViewportShaderHandle.GetAsset(ShaderAsset);
    shader_asset.mShader.Bind();

    self.mR2D.SetBuffers();
    self.mR2D.BindBuffers();

    self.mRenderContext.DrawIndexed(self.mViewportVertexArray, self.mViewportIndexBuffer.GetCount());
}
