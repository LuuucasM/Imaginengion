const std = @import("std");
const UniformBuffer = @import("../UniformBuffers/UniformBuffer.zig");
const Window = @import("../Windows/Window.zig");

const RenderContext = @import("RenderContext.zig");
const Renderer2D = @import("Renderer2D.zig");
const Renderer3D = @import("Renderer3D.zig");

const AssetManager = @import("../Assets/AssetManager.zig");
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

const LinAlg = @import("../Math/LinAlg.zig");
const Vec3f32 = LinAlg.Vec3f32;
const Quatf32 = LinAlg.Quatf32;

const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;

const Tracy = @import("../Core/Tracy.zig");

const Renderer = @This();

var RenderManager: Renderer = .{};

pub const RenderStats = struct {
    mQuadNum: usize = 0,
    mCircleNum: usize = 0,
    mLineNum: usize = 0,
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

mR2D: Renderer2D = undefined,
mR3D: Renderer3D = undefined,

mCameraBuffer: CameraData = std.mem.zeroes(CameraData),
mCameraUniformBuffer: UniformBuffer = undefined,

mModeBuffer: ModeData = std.mem.zeroes(ModeData),
mModeUniformBuffer: UniformBuffer = undefined,

mSDFShader: AssetHandle = undefined,

var RenderAllocator = std.heap.DebugAllocator(.{}).init;

pub fn Init(window: *Window) !void {
    RenderManager.mRenderContext = RenderContext.Init(window);

    RenderManager.mR2D = try Renderer2D.Init(RenderAllocator.allocator());
    RenderManager.mR3D = Renderer3D.Init();

    RenderManager.mCameraUniformBuffer = UniformBuffer.Init(@sizeOf(CameraData));
    RenderManager.mModeUniformBuffer = UniformBuffer.Init(@sizeOf(ModeData));

    RenderManager.mSDFShader = try AssetManager.GetAssetHandleRef("assets/shaders/SDFShader.program", .Eng);
}

pub fn Deinit() !void {
    try RenderManager.mR2D.Deinit();
    RenderManager.mCameraUniformBuffer.Deinit();

    RenderAllocator.deinit();
}

pub fn SwapBuffers() void {
    RenderManager.mRenderContext.PushDebugGroup("Swap Buffers\x00");
    defer RenderManager.mRenderContext.PopDebugGroup();
    RenderManager.mRenderContext.SwapBuffers();
}

//mode bit 0: set to 1 for aspect ratio correction, 0 for not
pub fn OnUpdate(scene_manager: *SceneManager, camera_component: *CameraComponent, camera_transform: *TransformComponent, frame_allocator: std.mem.Allocator, mode: u32) !void {
    const zone = Tracy.ZoneInit("Renderer OnUpdate", @src());
    defer zone.Deinit();

    RenderManager.mRenderContext.PushDebugGroup("Frame\x00");
    defer RenderManager.mRenderContext.PopDebugGroup();

    std.debug.assert(mode == 0b0 or mode == 0b1);

    UpdateCameraBuffer(camera_component, camera_transform);
    UpdateModeBuffer(mode);
    BeginRendering();

    //get all the shapes minus the children because we will render them with the parents
    const shapes_ids = try scene_manager.GetEntityGroup(GroupQuery{
        .Not = .{
            .mFirst = GroupQuery{
                .Or = &[_]GroupQuery{
                    GroupQuery{ .Component = QuadComponent },
                    GroupQuery{ .Component = TextComponent },
                },
            },
            .mSecond = GroupQuery{ .Component = EntityChildComponent },
        },
    }, frame_allocator);

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
        try DrawShape(shape_entity, &base_transform_component);
    }

    try EndRendering(camera_component);
}

pub fn GetRenderStats() RenderStats {
    return RenderManager.mStats;
}

pub fn GetSDFShader() !*ShaderAsset {
    return try RenderManager.mSDFShader.GetAsset(ShaderAsset);
}

fn UpdateCameraBuffer(camera_component: *CameraComponent, camera_transform: *TransformComponent) void {
    RenderManager.mCameraBuffer.mRotation = [4]f32{ camera_transform.Rotation[0], camera_transform.Rotation[1], camera_transform.Rotation[2], camera_transform.Rotation[3] };
    RenderManager.mCameraBuffer.mPosition = [3]f32{ camera_transform.Translation[0], camera_transform.Translation[1], camera_transform.Translation[2] };
    RenderManager.mCameraBuffer.mPerspectiveFar = camera_component.mPerspectiveFar;
    RenderManager.mCameraBuffer.mResolutionWidth = @floatFromInt(camera_component.mViewportWidth);
    RenderManager.mCameraBuffer.mResolutionHeight = @floatFromInt(camera_component.mViewportHeight);
    RenderManager.mCameraBuffer.mAspectRatio = camera_component.mAspectRatio;
    RenderManager.mCameraBuffer.mFOV = camera_component.mPerspectiveFOVRad;
}

fn UpdateModeBuffer(mode: u32) void {
    RenderManager.mModeBuffer.mMode = mode;
}

fn BeginRendering() void {
    const zone = Tracy.ZoneInit("BeginRendering", @src());
    defer zone.Deinit();

    RenderManager.mRenderContext.PushDebugGroup("Set Camera Data\x00");
    defer RenderManager.mRenderContext.PopDebugGroup();

    RenderManager.mCameraUniformBuffer.SetData(&RenderManager.mCameraBuffer, @sizeOf(CameraData), 0);
    RenderManager.mModeUniformBuffer.SetData(&RenderManager.mModeBuffer, @sizeOf(ModeData), 0);

    RenderManager.mStats = std.mem.zeroes(RenderStats);

    RenderManager.mR2D.StartBatch();
}

fn DrawChildren(entity: Entity, parent_transform: *TransformComponent) !void {
    const zone = Tracy.ZoneInit("Renderer DrawChildren", @src());
    defer zone.Deinit();

    const parent_component = entity.GetComponent(EntityParentComponent).?;

    var curr_id = parent_component.mFirstChild;

    while (true) : (if (curr_id == parent_component.mFirstChild) break) {
        const child_entity = Entity{ .mEntityID = curr_id, .mECSManagerRef = entity.mECSManagerRef };

        try DrawShape(child_entity, parent_transform);

        const child_component = child_entity.GetComponent(EntityChildComponent).?;
        curr_id = child_component.mNext;
    }
}

fn DrawShape(entity: Entity, parent_transform: *TransformComponent) anyerror!void {
    const zone = Tracy.ZoneInit("Renderer Draw Shape", @src());
    defer zone.Deinit();

    const transform_component = entity.GetComponent(TransformComponent).?;
    parent_transform.Translation += transform_component.Translation;
    parent_transform.Rotation = LinAlg.QuatMulQuat(parent_transform.Rotation, transform_component.Rotation);
    parent_transform.Scale += transform_component.Scale;

    //check for specific shapes and draw them if they exist
    if (entity.GetComponent(QuadComponent)) |quad_component| {
        try RenderManager.mR2D.DrawQuad(parent_transform, quad_component);
    }
    if (entity.GetComponent(TextComponent)) |text_component| {
        try RenderManager.mR2D.DrawText(parent_transform, text_component);
    }

    //check is if parent, if so draw children else nothing
    if (entity.GetComponent(EntityParentComponent)) |parent_component| {
        _ = parent_component;
        try DrawChildren(entity, parent_transform);
    }
}

fn EndRendering(camera_component: *CameraComponent) !void {
    const zone = Tracy.ZoneInit("Renderer EndRendering", @src());
    defer zone.Deinit();

    RenderManager.mRenderContext.PushDebugGroup("End Rendering\x00");
    defer RenderManager.mRenderContext.PopDebugGroup();

    camera_component.mViewportFrameBuffer.Bind();
    defer camera_component.mViewportFrameBuffer.Unbind();

    const sdf_shader_asset = try RenderManager.mSDFShader.GetAsset(ShaderAsset);
    sdf_shader_asset.Bind();

    try RenderManager.mR2D.SetBuffers();

    //UBOs
    RenderManager.mCameraUniformBuffer.Bind(0);
    RenderManager.mModeUniformBuffer.Bind(1);

    RenderManager.mR2D.BindBuffers();

    RenderManager.mRenderContext.PushDebugGroup("Draw Indexed\x00");
    RenderManager.mRenderContext.DrawIndexed(camera_component.mViewportVertexArray, camera_component.mViewportIndexBuffer.GetCount());
    RenderManager.mRenderContext.PopDebugGroup();
}
