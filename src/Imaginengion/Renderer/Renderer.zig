const std = @import("std");
const UniformBuffer = @import("../UniformBuffers/UniformBuffer.zig");
const Window = @import("../Windows/Window.zig");

const Renderer2D = @import("Renderer2D.zig");
const Renderer3D = @import("Renderer3D.zig");

const ShaderAsset = @import("../Assets/Assets.zig").ShaderAsset;
const AssetHandle = @import("../Assets/AssetHandle.zig");

const SceneManager = @import("../Scene/SceneManager.zig");

const MathTypes = @import("../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;
const Vec4 = MathTypes.Vec4;

const Entity = @import("../GameObjects/Entity.zig");
const EntityComponents = @import("../GameObjects/Components.zig");
const TransformComponent = EntityComponents.TransformComponent;
const QuadComponent = EntityComponents.QuadComponent;
const TextComponent = EntityComponents.TextComponent;
const EntitySceneComponent = EntityComponents.EntitySceneComponent;
const EntityChildComponent = @import("../ECS/Components.zig").ChildComponent(Entity.Type);
const EntityParentComponent = @import("../ECS/Components.zig").ParentComponent(Entity.Type);
const EngineContext = @import("../Core/EngineContext.zig");
const FrameBuffer = @import("../FrameBuffers/FrameBuffer.zig").FrameBuffer;
const TextureFormat = @import("../Assets/Assets.zig").Texture2D.TextureFormat;
const RenderPlatform = @import("RenderPlatform.zig");
const TextureManager = @import("../TextureManager/TextureManager.zig");
const RenderPipeline = @import("RenderPipeline.zig");
const PushConstants = RenderPipeline.SDFPushConstants;

const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;

const Tracy = @import("../Core/Tracy.zig");

const Renderer = @This();

pub const OutputFrameBuffer = FrameBuffer(&[_]TextureFormat{.RGBA8}, .None, 1);
pub const GamePipielineT = RenderPipeline.Pipeline(.GameShader);
pub const OverlayPipelineT = RenderPipeline.Pipeline(.OverlayShader);

pub const ShadingData = extern struct {
    pub const SHADING_FLAG_TRANSPARENT: u32 = 1 << 0;

    //texture data
    TextureUV0: Vec2(f32).VectorT,
    TextureUV1: Vec2(f32).VectorT,
    TilingFactor: f32, //note this one has to be a single f32 so that it packs into the Absorption Vec3 well

    //material volume data
    Absorption: Vec3(f32).VectorT,

    //material surface data
    Color: Vec4(f32).VectorT,

    Texturehandle: u32,
    SiblingShading: u32,
    _pad0: [2]f32 = [2]f32{ 0, 0 },
};

pub const ShapeType = enum(u32) {
    None = 0,
    Quad,
    Glyph,
};

mPlatform: RenderPlatform = .{},
mTextureManager: TextureManager = .{},
mGamePipeline: GamePipielineT = .{},
mOverlayPipeline: OverlayPipelineT = .{},
mIntermediateFB: OutputFrameBuffer = .{},
mSDFPushConstants: PushConstants = undefined,
mR2D: Renderer2D = .{},
mR3D: Renderer3D = .{},

pub fn Init(self: *Renderer, engine_context: *EngineContext) !void {
    self.mPlatform.Init(engine_context);

    try self.mTextureManager.Init(engine_context, 2_000_000_000);

    try self.mGamePipeline.Init(engine_context);

    try self.mR2D.Init(engine_context);
    self.mR3D.Init();
}

pub fn Deinit(self: *Renderer, engine_context: *EngineContext) void {
    self.mSDFShader.Deinit(engine_context) catch unreachable;
    self.mTextureManager.Deinit(engine_context);
    self.mPipeline.Deinit(engine_context);
    self.mR2D.Deinit(engine_context);
    self.mR3D.Deinit(engine_context.EngineAllocator());
    self.mPlatform.Deinit(&engine_context.mAppWindow);
}

//mode bit 0: set to 1 for aspect ratio correction, 0 for not
pub fn OnUpdate(self: *Renderer, world_type: EngineContext.WorldType, engine_context: *EngineContext, push_constants: PushConstants, frame_buffer: *OutputFrameBuffer) !void {
    const zone = Tracy.ZoneInit("Renderer::OnUpdate", @src());
    defer zone.Deinit();

    if (!self.mPlatform.BeginFrame(&engine_context.mAppWindow)) return;

    self.mPlatform.PushDebugGroup("Frame\x00");

    const scene_manager = switch (world_type) {
        .Game => &engine_context.mGameWorld,
        .Editor => &engine_context.mEditorWorld,
        .Simulate => &engine_context.mSimulateWorld,
    };

    self.mSDFPushConstants = push_constants;

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

    switch (world_type) {
        .Game => engine_context.mEngineStats.GameWorldStats.mRenderStats.TotalObjects = shapes_ids.items.len,
        .Editor => engine_context.mEngineStats.EditorWorldStats.mRenderStats.TotalObjects = shapes_ids.items.len,
        .Simulate => engine_context.mEngineStats.SimulateWorldStats.mRenderStats.TotalObjects = shapes_ids.items.len,
    }

    //TODO: culling
    //TODO: sorting
    //TODO: other optimizsations?

    for (shapes_ids.items) |shape_id| {
        const shape_entity = scene_manager.GetEntity(shape_id);
        try self.DrawShape(engine_context, shape_entity);
    }

    try self.EndRendering(world_type, engine_context, frame_buffer);
}

fn BeginRendering(self: *Renderer, engine_allocator: std.mem.Allocator) void {
    const zone = Tracy.ZoneInit("BeginFrame", @src());
    defer zone.Deinit();

    self.mR2D.StartBatch(engine_allocator);
}

fn DrawShape(self: *Renderer, engine_context: *EngineContext, entity: Entity) anyerror!void {
    const zone = Tracy.ZoneInit("Renderer Draw Shape", @src());
    defer zone.Deinit();

    const transform_component = entity.GetComponent(TransformComponent).?;
    const entity_scene_comp = entity.GetComponent(EntitySceneComponent).?;

    //check for specific shapes and draw them if they exist
    if (entity.GetComponent(QuadComponent)) |quad_component| {
        try self.mR2D.DrawQuad(engine_context, transform_component, quad_component, entity_scene_comp);
    }
    if (entity.GetComponent(TextComponent)) |text_component| {
        try self.mR2D.DrawText(engine_context, transform_component, text_component, entity_scene_comp);
    }
}

fn EndRendering(self: *Renderer, world_type: EngineContext.WorldType, engine_context: *EngineContext, frame_buffer: *OutputFrameBuffer) !void {
    const zone = Tracy.ZoneInit("Renderer EndRendering", @src());
    defer zone.Deinit();

    self.mPlatform.PushDebugGroup("End Rendering\x00");

    const cmd = self.mPlatform.GetCommandBuff();
    self.mIntermediateFB.Resize(engine_context, frame_buffer.GetWidth(), frame_buffer.GetHeight());

    //====================first overlay render pipeline======================================
    self.mPlatform.PushDebugGroup("Upload Buffers - Overlay\x00");
    try self.mR2D.SetBuffers(world_type, engine_context, .OverlayPipeline);
    self.mPlatform.PopDebugGroup();

    self.mPlatform.PushDebugGroup("Draw - Overlay\x00");
    const overlay_render_pass = self.mIntermediateFB.BeginRenderPass(engine_context);

    self.mOverlayPipeline.Bind(overlay_render_pass);

    self.mR2D.BindBuffers(overlay_render_pass, .OverlayPipeline);

    self.mTextureManager.Bind(overlay_render_pass);

    self.mSDFPushConstants.mQuadsCount = self.mR2D.GetBufferCount(.Quad, .OverlayPipeline);
    self.mSDFPushConstants.mGlyphsCount = self.mR2D.GetBufferCount(.Glyph, .OverlayPipeline);
    self.mOverlayPipeline.PushUniforms(cmd, self.mPushConstants);

    self.mOverlayPipeline.Draw(overlay_render_pass);
    self.mPlatform.PopDebugGroup(); //pop Draw DebugGroup

    self.mIntermediateFB.EndRenderPass(overlay_render_pass);
    //=======================================end overlay render pipeline============================

    //=====================================now for game layer render pipeline======================================================
    self.mPlatform.PushDebugGroup("Upload Buffers - Game\x00");
    try self.mR2D.SetBuffers(world_type, engine_context, .GamePipeline);
    self.mPlatform.PopDebugGroup();

    self.mPlatform.PushDebugGroup("Draw - Game\x00");
    const game_render_pass = frame_buffer.BeginRenderPass(engine_context);

    self.mGamePipeline.Bind(game_render_pass);

    self.mR2D.BindBuffers(game_render_pass, .GamePipeline);

    self.mTextureManager.Bind(game_render_pass);

    self.mIntermediateFB.Bind(game_render_pass, 0, 1);

    self.mSDFPushConstants.mQuadsCount = self.mR2D.GetBufferCount(.Quad, .GamePipeline);
    self.mSDFPushConstants.mGlyphsCount = self.mR2D.GetBufferCount(.Glyph, .GamePipeline);
    self.mGamePipeline.PushUniforms(cmd, self.mPushConstants);

    self.mGamePipeline.Draw(game_render_pass);
    self.mPlatform.PopDebugGroup(); //pop Draw DebugGroup

    frame_buffer.EndRenderPass(game_render_pass);
    //=====================================end game layer render pipeline ========================================================

    self.mPlatform.PopDebugGroup(); //pop end rendering group
    self.mPlatform.PopDebugGroup(); //pop frame group

    self.mPlatform.EndFrame();
}
