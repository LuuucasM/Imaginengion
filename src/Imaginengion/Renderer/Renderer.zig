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

mSDFShader: AssetHandle = .{},

pub fn Init(self: *Renderer, window: *Window, engine_context: *EngineContext) !void {
    const engine_allocator = engine_context.EngineAllocator();
    self.mRenderContext = RenderContext.Init(window);

    try self.mR2D.Init(engine_allocator);
    self.mR3D.Init();

    self.mCameraUniformBuffer = UniformBuffer.Init(@sizeOf(CameraData));
    self.mModeUniformBuffer = UniformBuffer.Init(@sizeOf(ModeData));

    self.mSDFShader = try engine_context.mAssetManager.GetAssetHandleRef(engine_context.EngineAllocator(), "assets/shaders/SDFShader.program", .Eng);
}

pub fn Deinit(self: *Renderer, engine_allocator: std.mem.Allocator) void {
    self.mR2D.Deinit(engine_allocator);
    self.mCameraUniformBuffer.Deinit();
}

pub fn SwapBuffers(self: *Renderer) void {
    self.mRenderContext.PushDebugGroup("Swap Buffers\x00");
    defer self.mRenderContext.PopDebugGroup();
    self.mRenderContext.SwapBuffers();
}

//mode bit 0: set to 1 for aspect ratio correction, 0 for not
pub fn OnUpdate(self: *Renderer, engine_context: *EngineContext, scene_manager: *SceneManager, camera_component: *CameraComponent, camera_transform: *TransformComponent, mode: u32) !void {
    std.debug.assert(mode == 0b0 or mode == 0b1);

    const zone = Tracy.ZoneInit("Renderer OnUpdate", @src());
    defer zone.Deinit();

    self.mRenderContext.PushDebugGroup("Frame\x00");
    defer self.mRenderContext.PopDebugGroup();

    self.UpdateCameraBuffer(camera_component, camera_transform);
    self.UpdateModeBuffer(mode);
    self.BeginRendering(engine_context.EngineAllocator());

    //get all the shapes minus the children because we will render them with the parents
    const shapes_ids = try scene_manager.GetEntityGroup(
        engine_context.FrameAllocator(),
        GroupQuery{
            .Not = .{
                .mFirst = GroupQuery{
                    .Or = &[_]GroupQuery{
                        GroupQuery{ .Component = QuadComponent },
                        GroupQuery{ .Component = TextComponent },
                    },
                },
                .mSecond = GroupQuery{ .Component = EntityChildComponent },
            },
        },
    );

    //TODO: sorting
    //TODO: culling
    //TODO: other optimizsations?

    //draw the shapes
    var base_transform_component = TransformComponent{};

    for (shapes_ids.items) |shape_id| {
        base_transform_component.SetTranslation(Vec3f32{ 0.0, 0.0, 0.0 });
        base_transform_component.SetRotation(Quatf32{ 1.0, 0.0, 0.0, 0.0 });
        base_transform_component.SetScale(Vec3f32{ 0.0, 0.0, 0.0 });

        const shape_entity = scene_manager.GetEntity(shape_id);
        try self.DrawShape(engine_context, shape_entity, &base_transform_component);
    }

    try self.EndRendering(engine_context, camera_component);
}

pub fn GetRenderStats(self: *Renderer) RenderStats {
    return self.mStats;
}

pub fn GetSDFShader(self: *Renderer, engine_context: *EngineContext) !*ShaderAsset {
    return try self.mSDFShader.GetAsset(engine_context, ShaderAsset);
}

fn UpdateCameraBuffer(self: *Renderer, camera_component: *CameraComponent, camera_transform: *TransformComponent) void {
    self.mCameraBuffer.mRotation = [4]f32{ camera_transform.Rotation[0], camera_transform.Rotation[1], camera_transform.Rotation[2], camera_transform.Rotation[3] };
    self.mCameraBuffer.mPosition = [3]f32{ camera_transform.Translation[0], camera_transform.Translation[1], camera_transform.Translation[2] };
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

fn DrawChildren(self: *Renderer, engine_context: *EngineContext, entity: Entity, parent_transform: *TransformComponent) !void {
    const zone = Tracy.ZoneInit("Renderer DrawChildren", @src());
    defer zone.Deinit();

    const parent_component = entity.GetComponent(EntityParentComponent).?;

    var curr_id = parent_component.mFirstChild;

    while (true) : (if (curr_id == parent_component.mFirstChild) break) {
        const child_entity = Entity{ .mEntityID = curr_id, .mECSManagerRef = entity.mECSManagerRef };

        try self.DrawShape(engine_context, child_entity, parent_transform);

        const child_component = child_entity.GetComponent(EntityChildComponent).?;
        curr_id = child_component.mNext;
    }
}

fn DrawShape(self: *Renderer, engine_context: *EngineContext, entity: Entity, parent_transform: *TransformComponent) anyerror!void {
    const zone = Tracy.ZoneInit("Renderer Draw Shape", @src());
    defer zone.Deinit();

    const transform_component = entity.GetComponent(TransformComponent).?;
    parent_transform.Translation += transform_component.Translation;
    parent_transform.Rotation = LinAlg.QuatMulQuat(parent_transform.Rotation, transform_component.Rotation);
    parent_transform.Scale += transform_component.Scale;

    //check for specific shapes and draw them if they exist
    if (entity.GetComponent(QuadComponent)) |quad_component| {
        try self.mR2D.DrawQuad(engine_context, parent_transform, quad_component);
    }
    if (entity.GetComponent(TextComponent)) |text_component| {
        try self.mR2D.DrawText(engine_context, parent_transform, text_component);
    }

    //check is if parent, if so draw children else nothing
    if (entity.GetComponent(EntityParentComponent)) |parent_component| {
        _ = parent_component;
        try self.DrawChildren(engine_context, entity, parent_transform);
    }
}

fn EndRendering(self: *Renderer, engine_context: *EngineContext, camera_component: *CameraComponent) !void {
    const zone = Tracy.ZoneInit("Renderer EndRendering", @src());
    defer zone.Deinit();

    self.mStats.mQuadNum = self.mR2D.mQuadBufferBase.items.len;
    self.mStats.mGlyphNum = self.mR2D.mGlyphBufferBase.items.len;

    self.mRenderContext.PushDebugGroup("End Rendering\x00");
    defer self.mRenderContext.PopDebugGroup();

    camera_component.mViewportFrameBuffer.Bind();
    defer camera_component.mViewportFrameBuffer.Unbind();

    const sdf_shader_asset = try self.mSDFShader.GetAsset(engine_context, ShaderAsset);
    sdf_shader_asset.Bind();

    try self.mR2D.SetBuffers();

    //UBOs
    self.mCameraUniformBuffer.Bind(0);
    self.mModeUniformBuffer.Bind(1);

    self.mR2D.BindBuffers();

    self.mRenderContext.PushDebugGroup("Draw Indexed\x00");
    self.mRenderContext.DrawIndexed(camera_component.mViewportVertexArray, camera_component.mViewportIndexBuffer.GetCount());
    self.mRenderContext.PopDebugGroup();
}
