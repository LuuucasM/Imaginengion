const std = @import("std");
const UniformBuffer = @import("../UniformBuffers/UniformBuffer.zig");
const Window = @import("../Windows/Window.zig");

const RenderContext = @import("RenderContext.zig");
const Renderer2D = @import("Renderer2D.zig");
const Renderer3D = @import("Renderer3D.zig");

const ShaderAsset = @import("../Assets/Assets.zig").ShaderAsset;
const AssetHandle = @import("../Assets/AssetHandle.zig");

const SceneManager = @import("../Scene/SceneManager.zig");

const Entity = @import("../GameObjects/Entity.zig");
const EntityComponents = @import("../GameObjects/Components.zig");
const TransformComponent = EntityComponents.TransformComponent;
const QuadComponent = EntityComponents.QuadComponent;
const TextComponent = EntityComponents.TextComponent;
const CameraComponent = EntityComponents.CameraComponent;
const EntityChildComponent = @import("../ECS/Components.zig").ChildComponent(Entity.Type);
const EntityParentComponent = @import("../ECS/Components.zig").ParentComponent(Entity.Type);
const EngineContext = @import("../Core/EngineContext.zig");

const LinAlg = @import("../Math/LinAlg.zig");
const Vec3f32 = LinAlg.Vec3f32;
const Quatf32 = LinAlg.Quatf32;

const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;

const Tracy = @import("../Core/Tracy.zig");

const Renderer = @This();

pub const RenderStats = struct {
    mQuadNum: usize = 0,
    mGlyphNum: usize = 0,
};

const CameraData = extern struct {
    mRotation: [4]f32, // 16 bytes ← 16-byte boundary
    mPosition: [3]f32, // 12 bytes
    mPerspectiveFar: f32, // 4 bytes  ← 16-byte boundary
    mResolutionWidth: f32, // 4 bytes
    mResolutionHeight: f32, // 4 bytes
    mAspectRatio: f32, // 4 bytes
    mFOV: f32, // 4 bytes ← 16-byte boundary
};

const ModeData = extern struct {
    mMode: u32,
};

mRenderContext: RenderContext = undefined,
mStats: RenderStats = .{},

mR2D: Renderer2D = .{},
mR3D: Renderer3D = .{},

mCameraBuffer: CameraData = std.mem.zeroes(CameraData),
mCameraUniformBuffer: UniformBuffer = undefined,

mModeBuffer: ModeData = std.mem.zeroes(ModeData),
mModeUniformBuffer: UniformBuffer = undefined,

mSDFShader: ShaderAsset = undefined,

pub fn Init(self: *Renderer, window: *Window, engine_context: *EngineContext) !void {
    const engine_allocator = engine_context.EngineAllocator();
    self.mRenderContext = RenderContext.Init(window);

    try self.mR2D.Init(engine_allocator);
    self.mR3D.Init();

    self.mCameraUniformBuffer = UniformBuffer.Init(@sizeOf(CameraData));
    self.mModeUniformBuffer = UniformBuffer.Init(@sizeOf(ModeData));

    const shader_rel_path = "assets/shaders/SDFShader.program";
    const shader_abs_path = try engine_context.mAssetManager.GetAbsPath(engine_context.FrameAllocator(), shader_rel_path, .Eng);
    const shader_file = try engine_context.mAssetManager.OpenFile(shader_rel_path, .Eng);
    try self.mSDFShader.Init(engine_context, shader_abs_path, shader_rel_path, shader_file);
}

pub fn Deinit(self: *Renderer, engine_context: *EngineContext) void {
    self.mR2D.Deinit(engine_context.EngineAllocator());
    self.mCameraUniformBuffer.Deinit();
    try self.mSDFShader.Deinit(engine_context);
}

pub fn SwapBuffers(self: *Renderer) void {
    self.mRenderContext.PushDebugGroup("Swap Buffers\x00");
    defer self.mRenderContext.PopDebugGroup();
    self.mRenderContext.SwapBuffers();
}

//mode bit 0: set to 1 for aspect ratio correction, 0 for not
pub fn OnUpdate(self: *Renderer, engine_context: *EngineContext, scene_manager: *SceneManager, camera_component: *CameraComponent, camera_transform: *TransformComponent, mode: u32) !void {
    std.debug.assert(mode == 0b0 or mode == 0b1);

    const zone = Tracy.ZoneInit("Renderer::OnUpdate", @src());
    defer zone.Deinit();

    self.mRenderContext.PushDebugGroup("Frame\x00");
    defer self.mRenderContext.PopDebugGroup();

    self.UpdateCameraBuffer(camera_component, camera_transform);
    self.UpdateModeBuffer(mode);
    self.BeginRendering(engine_context.EngineAllocator());

    //get all the shapes
    const shapes_ids = try scene_manager.GetEntityGroup(
        engine_context.FrameAllocator(),
        GroupQuery{
            .Or = &[_]GroupQuery{
                GroupQuery{ .Component = QuadComponent },
                GroupQuery{ .Component = TextComponent },
            },
        },
    );

    //TODO: sorting
    //TODO: culling
    //TODO: other optimizsations?

    for (shapes_ids.items) |shape_id| {
        const shape_entity = scene_manager.GetEntity(shape_id);
        try self.DrawShape(engine_context, shape_entity);
    }

    try self.EndRendering(camera_component);
}

pub fn GetRenderStats(self: *Renderer) RenderStats {
    return self.mStats;
}

pub fn GetSDFShader(self: *Renderer) *ShaderAsset {
    return &self.mSDFShader;
}

fn UpdateCameraBuffer(self: *Renderer, camera_component: *CameraComponent, camera_transform: *TransformComponent) void {
    const world_pos = camera_transform.GetWorldPosition();
    const world_rot = camera_transform.GetWorldRotation();

    self.mCameraBuffer.mRotation = [4]f32{ world_rot[0], world_rot[1], world_rot[2], world_rot[3] };
    self.mCameraBuffer.mPosition = [3]f32{ world_pos[0], world_pos[1], world_pos[2] };
    self.mCameraBuffer.mPerspectiveFar = camera_component.mPerspectiveFar;
    self.mCameraBuffer.mResolutionWidth = @floatFromInt(camera_component.mViewportWidth);
    self.mCameraBuffer.mResolutionHeight = @floatFromInt(camera_component.mViewportHeight);
    self.mCameraBuffer.mAspectRatio = camera_component.mAspectRatio;
    self.mCameraBuffer.mFOV = camera_component.mPerspectiveFOVRad;
}

fn UpdateModeBuffer(self: *Renderer, mode: u32) void {
    self.mModeBuffer.mMode = mode;
}

fn BeginRendering(self: *Renderer, engine_allocator: std.mem.Allocator) void {
    const zone = Tracy.ZoneInit("BeginRendering", @src());
    defer zone.Deinit();

    self.mRenderContext.PushDebugGroup("Set Camera Data\x00");
    defer self.mRenderContext.PopDebugGroup();

    self.mCameraUniformBuffer.SetData(&self.mCameraBuffer, @sizeOf(CameraData), 0);
    self.mModeUniformBuffer.SetData(&self.mModeBuffer, @sizeOf(ModeData), 0);

    self.mStats = std.mem.zeroes(RenderStats);

    self.mR2D.StartBatch(engine_allocator);
}

fn DrawChildren(self: *Renderer, engine_context: *EngineContext, entity: Entity) !void {
    const zone = Tracy.ZoneInit("Renderer DrawChildren", @src());
    defer zone.Deinit();

    const parent_component = entity.GetComponent(EntityParentComponent).?;

    var curr_id = parent_component.mFirstChild;

    while (true) : (if (curr_id == parent_component.mFirstChild) break) {
        const child_entity = Entity{ .mEntityID = curr_id, .mECSManagerRef = entity.mECSManagerRef };

        try self.DrawShape(engine_context, child_entity);

        const child_component = child_entity.GetComponent(EntityChildComponent).?;
        curr_id = child_component.mNext;
    }
}

fn DrawShape(self: *Renderer, engine_context: *EngineContext, entity: Entity) anyerror!void {
    const zone = Tracy.ZoneInit("Renderer Draw Shape", @src());
    defer zone.Deinit();

    const transform_component = entity.GetComponent(TransformComponent).?;

    //check for specific shapes and draw them if they exist
    if (entity.GetComponent(QuadComponent)) |quad_component| {
        try self.mR2D.DrawQuad(engine_context, transform_component, quad_component);
    }
    if (entity.GetComponent(TextComponent)) |text_component| {
        try self.mR2D.DrawText(engine_context, transform_component, text_component);
    }

    //check is if parent, if so draw children else nothing
    if (entity.GetComponent(EntityParentComponent)) |parent_component| {
        _ = parent_component;
        try self.DrawChildren(engine_context, entity);
    }
}

fn EndRendering(self: *Renderer, camera_component: *CameraComponent) !void {
    const zone = Tracy.ZoneInit("Renderer EndRendering", @src());
    defer zone.Deinit();

    self.mStats.mQuadNum = self.mR2D.mQuadBufferBase.items.len;
    self.mStats.mGlyphNum = self.mR2D.mGlyphBufferBase.items.len;

    self.mRenderContext.PushDebugGroup("End Rendering\x00");
    defer self.mRenderContext.PopDebugGroup();

    camera_component.mViewportFrameBuffer.Bind();
    defer camera_component.mViewportFrameBuffer.Unbind();

    self.mSDFShader.Bind();

    try self.mR2D.SetBuffers();

    //UBOs
    self.mCameraUniformBuffer.Bind(0);
    self.mModeUniformBuffer.Bind(1);

    self.mR2D.BindBuffers();

    self.mRenderContext.PushDebugGroup("Draw Indexed\x00");
    self.mRenderContext.DrawIndexed(camera_component.mViewportVertexArray, camera_component.mViewportIndexBuffer.GetCount());
    self.mRenderContext.PopDebugGroup();
}
