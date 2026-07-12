const std = @import("std");
const UniformBuffer = @import("../UniformBuffers/UniformBuffer.zig");
const Window = @import("../Windows/Window.zig");
const SSBO = @import("../SSBOs/SSBO.zig");

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
const ComputeTexture = @import("../ComputeTexture/ComputeTexture.zig").ComputeStorageTexture;
const PushConstants = RenderPipeline.SDFPushConstants;

const SDFPipeline = @import("backends/SDFPipeline.zig").SDFPipeline;

const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;

const Tracy = @import("../Core/Tracy.zig");

const Renderer = @This();

pub const ComputeOutput = ComputeTexture(.BGRA8);

pub const OutputFrameBuffer = FrameBuffer(&[_]TextureFormat{.RGBA8}, .None, 1);
pub const GamePipielineT = RenderPipeline.Pipeline(.GamePipeline);
pub const OverlayPipelineT = RenderPipeline.Pipeline(.OverlayPipeline);

pub const EShadingFlags = enum(u32) {
    SURFACE_TRANSPARENT = 1 << 0,

    pub fn ToInt(self: EShadingFlags) u32 {
        return @intFromEnum(self);
    }
};

pub const SurfShadingData = extern struct {
    Color: Vec4(f32).VectorT,
    TextureUV0: Vec2(f32).VectorT,
    TextureUV1: Vec2(f32).VectorT,
    TilingFactor: f32,
    Texturehandle: u32,
    SiblingShading: u32,
    _pad0: f32 = 9.9,
};

pub const MedShadingData = extern struct {
    Absorption: Vec3(f32).VectorT,
    Scattering: Vec3(f32).VectorT,
};

pub const ShapeType = enum(u32) {
    None = 0,
    Quad,
    Glyph,
};

pub const ShadingBuffers = struct {
    mSurfShadingBuff: SSBO = .{},
    mSurfShadingBuffBase: std.ArrayList(SurfShadingData) = .empty,
    mMedShadingBuff: SSBO = .{},
    mMedShadingBuffBase: std.ArrayList(MedShadingData) = .empty,
    pub fn Init(self: *ShadingBuffers, engine_context: *EngineContext) !void {
        self.mSurfShadingBuff.Init(engine_context, @sizeOf(SurfShadingData) * 100, 4, .Fragment);
        self.mSurfShadingBuffBase = try std.ArrayList(SurfShadingData).initCapacity(engine_context.EngineAllocator(), 100);

        self.mMedShadingBuff.Init(engine_context, @sizeOf(MedShadingData) * 100, 4, .Fragment);
        self.mMedShadingBuffBase = try std.ArrayList(MedShadingData).initCapacity(engine_context.EngineAllocator(), 100);
    }
    pub fn Deinit(self: *ShadingBuffers, engine_context: *EngineContext) void {
        self.mSurfShadingBuff.Deinit(engine_context);
        self.mSurfShadingBuffBase.deinit(engine_context.EngineAllocator());

        self.mMedShadingBuff.Deinit(engine_context);
        self.mMedShadingBuffBase.deinit(engine_context.EngineAllocator());
    }
    pub fn AddSurface(self: *ShadingBuffers, engine_allocator: std.mem.Allocator, color: Vec4(f32), texture_uv0: Vec2(f32), texture_uv1: Vec2(f32), tiling_factor: f32, texture_handle: u32, sibling_shading: u32) usize {
        self.mSurfShadingBuffBase.append(engine_allocator, .{
            .Color = color.ToVector(),
            .TextureUV0 = texture_uv0.ToVector(),
            .TextureUV1 = texture_uv1.ToVector(),
            .TilingFactor = tiling_factor,
            .Texturehandle = texture_handle,
            .SiblingShading = sibling_shading,
        });

        return self.mSurfShadingBuffBase.items.len - 1;
    }
    pub fn AddMedium(self: *ShadingBuffers, engine_allocator: std.mem.Allocator, absorption: Vec3(f32), scattering: Vec3(f32)) void {
        self.mMedShadingBuffBase.append(engine_allocator, .{
            .Absorption = absorption.ToVector(),
            .Scattering = scattering.ToVector(),
        });
    }
    pub fn ClearAndFree(self: *ShadingBuffers, engine_allocator: std.mem.Allocator) void {
        self.mSurfShadingBuffBase.clearAndFree(engine_allocator);
        self.mMedShadingBuffBase.clearAndFree(engine_allocator);
    }
    pub fn SetBuffers(self: *ShadingBuffers, world_type: EngineContext.WorldType, engine_context: *EngineContext) !void {
        const zone = Tracy.ZoneInit("R2D SetBuffers", @src());
        defer zone.Deinit();

        const surf_byte_size = self.mSurfShadingBuffBase.items.len * @sizeOf(SurfShadingData);
        const med_byte_size = self.mMedShadingBuffBase.items.len * @sizeOf(MedShadingData);

        //shadings
        _ = self.mSurfShadingBuff.SetData(engine_context, self.mSurfShadingBuffBase.items.ptr, surf_byte_size, 0);
        _ = self.mSurfShadingBuff.SetData(engine_context, self.mMedShadingBuffBase.items.ptr, med_byte_size, 0);

        //fill out stats
        switch (world_type) {
            .Game => {
                engine_context.mEngineStats.GameWorldStats.mRenderStats.Shadings.TotalShadings = self.mSurfShadingBuffBase.items.len + self.mMedShadingBuffBase.items.len;
                engine_context.mEngineStats.GameWorldStats.mRenderStats.Shadings.SurfShadings = self.mSurfShadingBuffBase.items.len;
                engine_context.mEngineStats.GameWorldStats.mRenderStats.Shadings.MedShadings = self.mMedShadingBuffBase.items.len;
            },
            .Editor => {
                engine_context.mEngineStats.EditorWorldStats.mRenderStats.Shadings.TotalShadings = self.mSurfShadingBuffBase.items.len + self.mMedShadingBuffBase.items.len;
                engine_context.mEngineStats.EditorWorldStats.mRenderStats.Shadings.SurfShadings = self.mSurfShadingBuffBase.items.len;
                engine_context.mEngineStats.EditorWorldStats.mRenderStats.Shadings.MedShadings = self.mMedShadingBuffBase.items.len;
            },
            .Simulate => {
                engine_context.mEngineStats.SimulateWorldStats.mRenderStats.Shadings.TotalShadings = self.mSurfShadingBuffBase.items.len + self.mMedShadingBuffBase.items.len;
                engine_context.mEngineStats.SimulateWorldStats.mRenderStats.Shadings.SurfShadings = self.mSurfShadingBuffBase.items.len;
                engine_context.mEngineStats.SimulateWorldStats.mRenderStats.Shadings.MedShadings = self.mMedShadingBuffBase.items.len;
            },
        }
    }
    pub fn BindBuffers(self: ShadingBuffers, render_pass: *anyopaque) void {
        self.mSurfShadingBuff.Bind(render_pass);
        self.mMedShadingBuff.Bind(render_pass);
    }
};

mPlatform: RenderPlatform = .{},
mTextureManager: TextureManager = .{},
mOverlayPipeline: SDFPipeline(.Overlay) = .empty,
mGamePipeline: SDFPipeline(.Game) = .empty,
mSDFPushConstants: PushConstants = undefined,
mR2D: Renderer2D = .{},
mR3D: Renderer3D = .{},
mSDFShading: ShadingBuffers = .{},

pub fn Init(self: *Renderer, engine_context: *EngineContext) !void {
    self.mPlatform.Init(engine_context);

    try self.mTextureManager.Init(engine_context, 1_000_000_000);

    try self.mGamePipeline.Init(engine_context);
    try self.mOverlayPipeline.Init(engine_context);

    try self.mR2D.Init(engine_context);
    self.mR3D.Init();

    try self.mSDFShading.Init(engine_context);
}

pub fn Deinit(self: *Renderer, engine_context: *EngineContext) void {
    self.mSDFShading.Deinit(engine_context);
    self.mTextureManager.Deinit(engine_context);
    self.mGamePipeline.Deinit(engine_context);
    self.mOverlayPipeline.Deinit(engine_context);
    self.mR2D.Deinit(engine_context);
    self.mR3D.Deinit(engine_context.EngineAllocator());
    self.mPlatform.Deinit(&engine_context.mAppWindow);
}

//mode bit 0: set to 1 for aspect ratio correction, 0 for not
pub fn OnUpdate(self: *Renderer, world_type: EngineContext.WorldType, engine_context: *EngineContext, push_constants: PushConstants, compute_texture: *ComputeOutput) !void {
    const zone = Tracy.ZoneInit("Renderer::OnUpdate", @src());
    defer zone.Deinit();

    self.mPlatform.BeginFrame(&engine_context.mAppWindow);

    if (!self.mPlatform.HasFrame()) return;

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

    for (shapes_ids.items) |shape_id| {
        //TODO: distance based culling
        //because since rays have max distances we know if something is greater than the camera point to the object then we can ignore
        const shape_entity = scene_manager.GetEntity(shape_id);
        try self.DrawShape(engine_context, shape_entity);
    }

    //TODO: sorting
    //TODO: other optimizsations?

    try self.EndRendering(world_type, engine_context, compute_texture);
}

fn BeginRendering(self: *Renderer, engine_allocator: std.mem.Allocator) void {
    const zone = Tracy.ZoneInit("BeginFrame", @src());
    defer zone.Deinit();

    self.mR2D.StartBatch(engine_allocator);
    self.mSDFShading.ClearAndFree(engine_allocator);
}

fn DrawShape(self: *Renderer, engine_context: *EngineContext, entity: Entity) anyerror!void {
    const zone = Tracy.ZoneInit("Renderer Draw Shape", @src());
    defer zone.Deinit();

    const transform_component = entity.GetComponent(TransformComponent).?;
    const entity_scene_comp = entity.GetComponent(EntitySceneComponent).?;

    //check for specific shapes and draw them if they exist
    if (entity.GetComponent(QuadComponent)) |quad_component| {
        try self.mR2D.DrawQuad(
            engine_context,
            transform_component,
            quad_component,
            entity_scene_comp,
            &self.mSDFShading,
        );
    }
    if (entity.GetComponent(TextComponent)) |text_component| {
        try self.mR2D.DrawText(
            engine_context,
            transform_component,
            text_component,
            entity_scene_comp,
            &self.mSDFShading,
        );
    }
}

fn EndRendering(self: *Renderer, world_type: EngineContext.WorldType, engine_context: *EngineContext, compute_texture: *ComputeOutput) !void {
    const zone = Tracy.ZoneInit("Renderer EndRendering", @src());
    defer zone.Deinit();

    self.mPlatform.PushDebugGroup("End Rendering\x00");

    const cmd = self.mPlatform.GetCommandBuff();

    //====================first overlay render pipeline======================================
    self.mPlatform.PushDebugGroup("Upload Buffers - Overlay\x00");
    try self.mR2D.SetBuffers(world_type, engine_context, .OverlayPipeline);
    try self.mSDFShading.SetBuffers(world_type, engine_context);
    self.mPlatform.PopDebugGroup();

    self.mPlatform.PushDebugGroup("Draw - Overlay\x00");
    const overlay_compute_pass = compute_texture.BeginComputePass(engine_context, true);

    self.mOverlayPipeline.Bind(overlay_compute_pass);
    self.mR2D.BindBuffers(overlay_compute_pass, .OverlayPipeline);
    self.mSDFShading.BindBuffers(overlay_compute_pass);
    self.mTextureManager.Bind(overlay_compute_pass);

    self.mSDFPushConstants.mQuadsCount = self.mR2D.GetBufferCount(.Quad, .OverlayPipeline);
    self.mSDFPushConstants.mGlyphsCount = self.mR2D.GetBufferCount(.Glyph, .OverlayPipeline);
    self.mOverlayPipeline.PushUniforms(cmd, self.mSDFPushConstants);

    self.mOverlayPipeline.Dispatch(overlay_compute_pass, @intCast(compute_texture.GetWidth()), @intCast(compute_texture.GetHeight()));

    compute_texture.EndComputePass(overlay_compute_pass);
    self.mPlatform.PopDebugGroup(); //pop Draw DebugGroup
    //=======================================end overlay render pipeline============================

    //=====================================now for game layer render pipeline======================================================
    self.mPlatform.PushDebugGroup("Upload Buffers - Game\x00");
    try self.mR2D.SetBuffers(world_type, engine_context, .GamePipeline);
    try self.mSDFShading.SetBuffers(world_type, engine_context);
    self.mPlatform.PopDebugGroup();

    self.mPlatform.PushDebugGroup("Draw - Game\x00");
    const game_compute_pass = compute_texture.BeginComputePass(engine_context, false);

    self.mGamePipeline.Bind(game_compute_pass);
    self.mR2D.BindBuffers(game_compute_pass, .GamePipeline);
    self.mSDFShading.BindBuffers(game_compute_pass);
    self.mTextureManager.Bind(game_compute_pass);

    self.mSDFPushConstants.mQuadsCount = self.mR2D.GetBufferCount(.Quad, .GamePipeline);
    self.mSDFPushConstants.mGlyphsCount = self.mR2D.GetBufferCount(.Glyph, .GamePipeline);
    self.mGamePipeline.PushUniforms(cmd, self.mSDFPushConstants);

    self.mGamePipeline.Dispatch(game_compute_pass, @intCast(compute_texture.GetWidth()), @intCast(compute_texture.GetHeight()));

    compute_texture.EndComputePass(game_compute_pass);
    self.mPlatform.Present(compute_texture);
    self.mPlatform.PopDebugGroup(); //pop Draw DebugGroup
    //=====================================end game layer render pipeline ========================================================

    self.mPlatform.PopDebugGroup(); //pop end rendering group
    self.mPlatform.PopDebugGroup(); //pop frame group

    self.mPlatform.EndFrame();
}
