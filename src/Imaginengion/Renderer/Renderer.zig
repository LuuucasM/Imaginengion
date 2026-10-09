const std = @import("std");
const builtin = @import("builtin");
const UniformBuffer = @import("../UniformBuffers/UniformBuffer.zig");
const Window = @import("../Windows/Window.zig");
const SSBO = @import("../SSBOs/SSBO.zig");
const GPUAsserts = @import("../Core/GPUAsserts.zig");

const Renderer2D = @import("Renderer2D.zig");
const Renderer3D = @import("Renderer3D.zig");

const Assets = @import("../ECSComponents/AComponents.zig");
const AssetHandle = @import("../ECSObjects/AssetHandle.zig");
const ShaderAsset = Assets.ShaderAsset;
const Texture2D = Assets.Texture2D;

const WorldManager = @import("../Core/WorldManager.zig");

const MathTypes = @import("../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;
const Vec4 = MathTypes.Vec4;

const Entity = @import("../ECSObjects/Entity.zig");
const EntityComponents = @import("../ECSComponents/EComponents.zig");
const TransformComponent = EntityComponents.TransformComponent;
const ViewpointComponent = EntityComponents.ViewpointComponent;
const ShapeComponent = EntityComponents.ShapeComponent;
const SurfaceComponent = EntityComponents.SurfaceComponent;
const TextComponent = EntityComponents.TextComponent;
const EntityChildComponent = @import("../ECS/Components.zig").ChildComponent(Entity.Type);
const EntityParentComponent = @import("../ECS/Components.zig").ParentComponent(Entity.Type);
const EngineContext = @import("../Core/EngineContext.zig");
const RenderStats = @import("../Core/EngineStats.zig").RenderStats;
const Scene = @import("../ECSObjects/Scene.zig");
const FrameBuffer = @import("../FrameBuffers/FrameBuffer.zig").FrameBuffer;
const TextureFormat = @import("../ECSComponents/AComponents.zig").Texture2D.TextureFormat;
const RenderPlatform = @import("RenderPlatform.zig");
const FrameLimiter = @import("FrameLimiter.zig");
const PassPlan = @import("PassPlan.zig");
const TextureManager = @import("../TextureManager/TextureManager.zig");
const Viewports = @import("Viewports.zig");
const RenderTargetComponent = @import("../ECSComponents/Shared/RenderTargetComponent.zig");
const ViewportComponent = @import("../ECSComponents/Entity/ViewportComponent.zig");
const RenderPipeline = @import("RenderPipeline.zig");
const ComputeTexture = @import("../ComputeTexture/ComputeTexture.zig").ComputeStorageTexture;
const PushConstants = RenderPipeline.SDFPushConstants;

const MediumMaterial = @import("../Physics/MediumMaterial.zig");

const CameraRay = @import("../Math/CameraRay.zig");
const OverlayCanvas = @import("../Math/OverlayCanvas.zig");
const ShapeGeometry = @import("ShapeGeometry.zig");
const LayoutSystem = @import("../UI/LayoutSystem.zig");

const SDFPipeline = @import("backends/SDFPipeline.zig").SDFPipeline;

const GroupQuery = @import("../ECS/ECSManager.zig").GroupQuery;

const Tracy = @import("../Core/Tracy.zig");

const Renderer = @This();

pub const ComputeOutput = ComputeTexture(.RGBA8);

//pub const OutputFrameBuffer = FrameBuffer(&[_]TextureFormat{.RGBA8}, .None, 1);

pub const RenderingMode = enum {
    Overlay,
    Game,
    OverlayGame,
};

const ResetOptions = enum {
    ClearAndFree,
    ClearRetainingCapacity,
};

const is_spirv = builtin.target.cpu.arch.isSpirV();

//TODO: a setting the developer and the player can pick, once project and run settings are ported
const PRESENT_MODE: RenderPlatform.PresentMode = .VSync;
/// Frames a second at most, 0 for no limit. Works with either present mode
const FRAME_LIMIT: u32 = 0;

pub const SurfShadingData = extern struct {
    Color: if (is_spirv) Vec4(f32).VectorT else Vec4(f32).ArrayT,
    TextureUV0: if (is_spirv) Vec2(f32).VectorT else Vec2(f32).ArrayT,
    TextureUV1: if (is_spirv) Vec2(f32).VectorT else Vec2(f32).ArrayT,
    TilingFactor: f32,
    Texturehandle: u32,
    TextureWidth: u32,
    TextureHeight: u32,
};

pub const MedShadingData = extern struct {
    Color: if (is_spirv) Vec4(f32).VectorT else Vec4(f32).ArrayT,
    Absorption: if (is_spirv) Vec3(f32).VectorT else Vec3(f32).ArrayT,
    Scattering: if (is_spirv) Vec3(f32).VectorT else Vec3(f32).ArrayT align(16),
};

comptime {
    GPUAsserts.AssertGPULayout(SurfShadingData);
    GPUAsserts.AssertGPULayout(MedShadingData);
}

/// The camera this render looks through, which overlay scenes' canvases are placed in front of. Picking
/// takes the same one, so what it tests is where things were drawn.
pub const CameraView = struct {
    Pose: CameraRay.Pose,
    TanHalfFov: f32,
    //the size in pixels of what it's drawn into
    TargetWidth: f32,
    TargetHeight: f32,
    FarDistance: f32, //game layer shapes past this aren't drawn (overlay uses OverlayCanvas.FAR_DISTANCE)
    DisplayScale: f32, //the OS display scale, what ConstantPixelSize overlays size by

    /// The view of a camera entity, from its transform and viewpoint. The viewpoint's size has to
    /// already be set for this frame, since the target height comes from it.
    pub fn FromViewpoint(transform: *const TransformComponent, viewpoint: *const ViewpointComponent, display_scale: f32) CameraView {
        return .{
            .Pose = .{ .Position = transform.GetWorldPosition(), .Rotation = transform.GetWorldRotation() },
            .TanHalfFov = @tan(viewpoint.mPerspectiveFOVRad * 0.5),
            .TargetWidth = @floatFromInt(viewpoint.mViewportWidth),
            .TargetHeight = @floatFromInt(viewpoint.mViewportHeight),
            .FarDistance = viewpoint.mPerspectiveFar,
            .DisplayScale = display_scale,
        };
    }

    /// The ray this view traces through `pixel`, the same one the shaders build for it.
    pub fn PixelRay(transform: *const TransformComponent, viewpoint: *const ViewpointComponent, pixel: Vec2(f32)) CameraRay.Ray {
        const pose = CameraRay.Pose{ .Position = transform.GetWorldPosition(), .Rotation = transform.GetWorldRotation() };
        return CameraRay.MakeRay(pose, viewpoint.GetRayParams(), pixel);
    }
};

pub const ShapeType = enum(u32) {
    None = 0,
    Quad,
    Glyph,
    /// a compound SDF (MergeComponent), 2D: a plate in its root's plane, shaped by its program (SDFProgram)
    Merge,
};

pub const ShadingBuffers = struct {
    mSurfShadingBuff: SSBO = .{},
    mSurfShadingBuffBase: std.ArrayList(SurfShadingData) = .empty,
    mMedShadingBuff: SSBO = .{},
    mMedShadingBuffBase: std.ArrayList(MedShadingData) = .empty,
    /// each letter's atlas entry so far this render (GlyphSurface), emptied with the shadings by Reset
    mGlyphSurfaces: std.AutoHashMapUnmanaged(GlyphKey, u32) = .empty,

    /// Which letter of which font atlas an atlas entry is for: the atlas's texture manager slot and the letter's place
    /// in its font (TextLayout.GlyphPlacement.AtlasIndex)
    pub const GlyphKey = struct {
        AtlasTexture: u32,
        Glyph: u32,
    };

    pub fn Init(self: *ShadingBuffers, engine_context: *EngineContext) !void {
        self.mSurfShadingBuff.Init(engine_context, @sizeOf(SurfShadingData) * 100, 0, .Compute);
        self.mSurfShadingBuffBase = try std.ArrayList(SurfShadingData).initCapacity(engine_context.EngineAllocator(), 100);

        self.mMedShadingBuff.Init(engine_context, @sizeOf(MedShadingData) * 100, 1, .Compute);
        self.mMedShadingBuffBase = try std.ArrayList(MedShadingData).initCapacity(engine_context.EngineAllocator(), 100);
    }
    pub fn Deinit(self: *ShadingBuffers, engine_context: *EngineContext) void {
        self.mSurfShadingBuff.Deinit(engine_context);
        self.mSurfShadingBuffBase.deinit(engine_context.EngineAllocator());

        self.mMedShadingBuff.Deinit(engine_context);
        self.mMedShadingBuffBase.deinit(engine_context.EngineAllocator());
        self.mGlyphSurfaces.deinit(engine_context.EngineAllocator());
    }
    pub fn AddSurface(
        self: *ShadingBuffers,
        engine_allocator: std.mem.Allocator,
        tex_options: *Texture2D.TexOptions,
        texture_asset: *Texture2D,
    ) !usize {
        try self.mSurfShadingBuffBase.append(engine_allocator, .{
            .Color = tex_options.mColor.ToArray(),
            .TextureUV0 = tex_options.mTextureUV0.ToArray(),
            .TextureUV1 = tex_options.mTextureUV1.ToArray(),
            .TilingFactor = tex_options.mTilingFactor,
            .Texturehandle = @intCast(texture_asset.GetTextureHandle()),
            .TextureWidth = @intCast(texture_asset.GetWidth()),
            .TextureHeight = @intCast(texture_asset.GetHeight()),
        });

        return self.mSurfShadingBuffBase.items.len - 1;
    }
    /// AddSurface for a texture manager slot that isn't a Texture2D asset: a render target shown on a quad
    pub fn AddSurfaceSlot(
        self: *ShadingBuffers,
        engine_allocator: std.mem.Allocator,
        tex_options: *Texture2D.TexOptions,
        texture_handle: u32,
        width: usize,
        height: usize,
    ) !usize {
        try self.mSurfShadingBuffBase.append(engine_allocator, .{
            .Color = tex_options.mColor.ToArray(),
            .TextureUV0 = tex_options.mTextureUV0.ToArray(),
            .TextureUV1 = tex_options.mTextureUV1.ToArray(),
            .TilingFactor = tex_options.mTilingFactor,
            .Texturehandle = @intCast(texture_handle),
            .TextureWidth = @intCast(width),
            .TextureHeight = @intCast(height),
        });
        return self.mSurfShadingBuffBase.items.len - 1;
    }
    /// The atlas entry for one letter: where it is in its font's atlas, which is all the coverage test reads. Every glyph
    /// of that letter in that atlas shares the one entry, so a text's eleven e's add one, not eleven. What a glyph is
    /// painted with is its text's fill, which its ShapeSurface points at itself. Good until the next Reset
    pub fn GlyphSurface(
        self: *ShadingBuffers,
        engine_allocator: std.mem.Allocator,
        key: GlyphKey,
        atlas_width: usize,
        atlas_height: usize,
        uv0: Vec2(f32),
        uv1: Vec2(f32),
    ) !usize {
        const entry = try self.mGlyphSurfaces.getOrPut(engine_allocator, key);
        if (!entry.found_existing) {
            errdefer _ = self.mGlyphSurfaces.remove(key);
            try self.mSurfShadingBuffBase.append(engine_allocator, .{
                .Color = .{ 1.0, 1.0, 1.0, 1.0 },
                .TextureUV0 = uv0.ToArray(),
                .TextureUV1 = uv1.ToArray(),
                .TilingFactor = 1.0,
                .Texturehandle = key.AtlasTexture,
                .TextureWidth = @intCast(atlas_width),
                .TextureHeight = @intCast(atlas_height),
            });
            entry.value_ptr.* = @intCast(self.mSurfShadingBuffBase.items.len - 1);
        }
        return entry.value_ptr.*;
    }
    pub fn AddMedium(self: *ShadingBuffers, engine_allocator: std.mem.Allocator, color: Vec4(f32), absorption: Vec3(f32), scattering: Vec3(f32)) !usize {
        try self.mMedShadingBuffBase.append(engine_allocator, .{
            .Color = color.ToArray(),
            .Absorption = absorption.ToArray(),
            .Scattering = scattering.ToArray(),
        });

        return self.mMedShadingBuffBase.items.len - 1;
    }
    pub fn Reset(self: *ShadingBuffers, engine_allocator: std.mem.Allocator, reset_options: ResetOptions) void {
        switch (reset_options) {
            .ClearAndFree => {
                self.mSurfShadingBuffBase.clearAndFree(engine_allocator);
                self.mMedShadingBuffBase.clearAndFree(engine_allocator);
                self.mGlyphSurfaces.clearAndFree(engine_allocator);
            },
            .ClearRetainingCapacity => {
                self.mSurfShadingBuffBase.clearRetainingCapacity();
                self.mMedShadingBuffBase.clearRetainingCapacity();
                self.mGlyphSurfaces.clearRetainingCapacity();
            },
        }
    }
    pub fn SetBuffers(self: *ShadingBuffers, engine_context: *EngineContext, copy_pass: *anyopaque) !void {
        const zone = Tracy.ZoneInit("Renderer::ShadingBuffers::SetBuffers", @src());
        defer zone.Deinit();

        const surf_byte_size = self.mSurfShadingBuffBase.items.len * @sizeOf(SurfShadingData);
        const med_byte_size = self.mMedShadingBuffBase.items.len * @sizeOf(MedShadingData);

        //shadings
        _ = self.mSurfShadingBuff.SetData(engine_context, copy_pass, self.mSurfShadingBuffBase.items.ptr, surf_byte_size, 0);
        _ = self.mMedShadingBuff.SetData(engine_context, copy_pass, self.mMedShadingBuffBase.items.ptr, med_byte_size, 0);
    }
    /// Adds this draw's shadings to stats. Once a draw, since the overlay and game passes share the one set
    pub fn AddStats(self: ShadingBuffers, stats: *RenderStats) void {
        stats.Shadings.TotalShadings += self.mSurfShadingBuffBase.items.len + self.mMedShadingBuffBase.items.len;
        stats.Shadings.SurfShadings += self.mSurfShadingBuffBase.items.len;
        stats.Shadings.MedShadings += self.mMedShadingBuffBase.items.len;
    }
    pub fn BindBuffers(self: ShadingBuffers, render_pass: *anyopaque) void {
        self.mSurfShadingBuff.Bind(render_pass);
        self.mMedShadingBuff.Bind(render_pass);
    }
};

mPlatform: RenderPlatform = .{},
mFrameLimiter: FrameLimiter = .Init(FRAME_LIMIT),
mTextureManager: TextureManager = .{},
mOverlayPipeline: SDFPipeline(.Overlay) = .empty,
mGamePipeline: SDFPipeline(.Game) = .empty,
mSDFPushConstants: PushConstants = undefined,
mR2D: Renderer2D = .{},
mR3D: Renderer3D = .{},
mSDFShading: ShadingBuffers = .{},
/// The render targets the shapes being drawn show (ViewportComponent), copied into their slots at the start of the draw's
/// command buffer, before anything samples them
mShownCopies: std.ArrayList(RenderTargetComponent.Shown) = .empty,

pub fn Init(self: *Renderer, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("Renderer::Init", @src());
    defer zone.Deinit();
    self.mPlatform.Init(engine_context, PRESENT_MODE);

    try self.mTextureManager.Init(engine_context, 1_000_000_000);

    try self.mGamePipeline.Init(engine_context);
    try self.mOverlayPipeline.Init(engine_context);

    try self.mR2D.Init(engine_context);
    self.mR3D.Init();

    try self.mSDFShading.Init(engine_context);
}

/// False when the frame is skipped: the frame limit says it's too soon, or no window image is free to draw into yet
pub fn BeginFrame(self: *Renderer, engine_context: *EngineContext) bool {
    const now = std.Io.Timestamp.now(engine_context.Io(), .awake).toNanoseconds();
    if (!self.mFrameLimiter.IsDue(now)) return false;

    const began = self.mPlatform.BeginFrame(&engine_context.mAppWindow);
    if (began) {
        //only a frame that started counts against the limit, so one that found no image free is tried again next pass
        self.mFrameLimiter.FrameStarted(now);
        engine_context.mEngineStats.FrameAcquired();
    }
    return began;
}

pub fn EndFrame(self: *Renderer) void {
    self.mPlatform.EndFrame();
}

pub fn Deinit(self: *Renderer, engine_context: *EngineContext) void {
    self.mShownCopies.deinit(engine_context.EngineAllocator());
    self.mSDFShading.Deinit(engine_context);
    self.mTextureManager.Deinit(engine_context);
    self.mGamePipeline.Deinit(engine_context);
    self.mOverlayPipeline.Deinit(engine_context);
    self.mR2D.Deinit(engine_context);
    self.mR3D.Deinit(engine_context.EngineAllocator());
    self.mPlatform.Deinit(&engine_context.mAppWindow);
}

/// The per view uniforms every render hands the renderer, from the camera's transform and viewpoint. The viewpoint's
/// size has to be set for this frame before calling, since the ray params are derived from it. The shape counts and
/// flags are filled in by the renderer once it knows them.
pub fn BuildPushConstants(transform_component: *TransformComponent, viewpoint_component: *ViewpointComponent) PushConstants {
    const ray_params = viewpoint_component.GetRayParams();
    return .{
        .mPosition = transform_component.GetWorldPosition().ToArray(),
        .mRotation = transform_component.GetWorldRotation().ToArray(),
        .mRayScale = ray_params.Scale.ToArray(),
        .mRayOffset = ray_params.Offset.ToArray(),
        .mPerspectiveFar = viewpoint_component.mPerspectiveFar,
        .mShapesCount = 0,
        .mDirectCount = 0,
        .mViewportWidth = @floatFromInt(viewpoint_component.mViewportWidth),
        .mViewportHeight = @floatFromInt(viewpoint_component.mViewportHeight),
        .mFlags = 0,
    };
}

/// Which scenes a render draws, see ShapeGeometry.ViewScenes
pub const ViewScenes = ShapeGeometry.ViewScenes;

/// Draws what `view_scenes` shows of the world through the camera into compute_texture, and fills in stats with
/// what it drew
pub fn RenderWorld(self: *Renderer, world_manager: *WorldManager, view_scenes: ViewScenes, stats: *RenderStats, engine_context: *EngineContext, push_constants: PushConstants, camera_view: CameraView, compute_texture: *ComputeOutput, rendering_mode: RenderingMode) !void {
    const zone = Tracy.ZoneInit("Renderer::RenderWorld", @src());
    defer zone.Deinit();

    //the screen each overlay is drawn on is what its layout fits into
    try LayoutSystem.RecordViewArea(world_manager, view_scenes.Overlays, camera_view, engine_context);
    const view = try ShapeGeometry.GatherViewShapes(engine_context.FrameAllocator(), world_manager, camera_view, view_scenes, ShapeGeometry.VISUALS_QUERY);
    try self.RenderShapes(&view, stats, engine_context, push_constants, compute_texture, rendering_mode);
}

/// RenderWorld for only the shapes in one scene, e.g. one template out of the several open in the template editing world
pub fn RenderScene(self: *Renderer, scene: Scene, stats: *RenderStats, engine_context: *EngineContext, push_constants: PushConstants, camera_view: CameraView, compute_texture: *ComputeOutput, rendering_mode: RenderingMode) !void {
    const zone = Tracy.ZoneInit("Renderer::RenderScene", @src());
    defer zone.Deinit();

    const scene_id = [_]Scene.Type{scene.mID};
    const view_scenes: ViewScenes = switch (scene.GetLayer()) {
        .GameLayer => .{ .Game = .{ .One = scene.mID }, .Overlays = &.{} },
        .OverlayLayer => .{ .Game = .None, .Overlays = &scene_id },
    };
    try LayoutSystem.RecordViewArea(scene.mManager, view_scenes.Overlays, camera_view, engine_context);
    const view = try ShapeGeometry.GatherViewShapes(engine_context.FrameAllocator(), scene.mManager, camera_view, view_scenes, ShapeGeometry.VISUALS_QUERY);
    try self.RenderShapes(&view, stats, engine_context, push_constants, compute_texture, rendering_mode);
}

/// Draws shapes already gathered for a view (ShapeGeometry.GatherViewShapes), each carrying its canvas and its mask
fn RenderShapes(self: *Renderer, view: *const ShapeGeometry.ViewShapes, stats: *RenderStats, engine_context: *EngineContext, push_constants: PushConstants, compute_texture: *ComputeOutput, rendering_mode: RenderingMode) !void {
    self.mSDFPushConstants = push_constants;

    try self.BeginRendering(engine_context.EngineAllocator());
    try self.mR2D.SetMasks(engine_context.EngineAllocator(), &view.Masks);
    const shapes = view.Shapes.items;

    //added up over every draw this frame: a world drawn for two views counts both
    stats.TotalObjects += shapes.len;

    {
        //one zone for the whole loop rather than one per shape, which would swamp the timeline
        const draw_zone = Tracy.ZoneInit("Renderer::DrawShapes", @src());
        defer draw_zone.Deinit();
        draw_zone.Value(shapes.len);

        for (shapes) |shape| {
            //TODO: distance based culling
            //because since rays have max distances we know if something is greater than the camera point to the object then we can ignore
            try self.DrawShape(engine_context, shape, &view.Masks);
        }
    }

    self.mSDFShading.AddStats(stats);

    //TODO: sorting
    //TODO: other optimizsations?

    try self.EndRendering(stats, engine_context, compute_texture, rendering_mode);
}

fn BeginRendering(self: *Renderer, engine_allocator: std.mem.Allocator) !void {
    const zone = Tracy.ZoneInit("Renderer::BeginRendering", @src());
    defer zone.Deinit();

    self.mR2D.StartBatch(engine_allocator);
    self.mSDFShading.Reset(engine_allocator, .ClearRetainingCapacity);
    self.mShownCopies.clearRetainingCapacity();

    //NOTE: temporary just add air as the medium
    const air_mat = MediumMaterial.MediumDatabase.get(.Air);
    _ = try self.mSDFShading.AddMedium(engine_allocator, Vec4(f32){ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 }, air_mat.RenderData.Absorption, air_mat.RenderData.Scattering);
}

fn DrawShape(self: *Renderer, engine_context: *EngineContext, shape: ShapeGeometry.ViewShape, masks: *const ShapeGeometry.ViewMasks) anyerror!void {
    const entity = shape.Entity;
    //a merge is drawn as one shape for all its parts, whether its root has a shape, a surface or a transform or not
    if (shape.Merge) return self.mR2D.DrawMerge(engine_context, entity, shape.Canvas, shape.Mask, masks, &self.mSDFShading);
    const transform_component = entity.GetComponent(TransformComponent).?;

    //a surface paints whatever the entity has, its shape or its text. a hidden one is skipped here and by picking
    //alike, so nothing can be clicked that isn't drawn. an overlay shape's canvas places it in front of this view's
    //camera, and sends it to the overlay pass
    const surface = entity.GetComponent(SurfaceComponent) orelse return;
    if (!surface.mShouldRender) return;

    if (entity.GetComponent(ShapeComponent)) |shape_component| {
        switch (shape_component.mKind) {
            .Quad => |quad| {
                //a quad showing a player's view samples its render target instead of its texture
                const shown = if (entity.GetComponent(ViewportComponent)) |viewport| try Viewports.ShownTarget(engine_context, viewport.*) else null;
                if (shown) |target| try self.mShownCopies.append(engine_context.EngineAllocator(), target);
                try self.mR2D.DrawQuad(
                    engine_context,
                    transform_component,
                    quad,
                    surface,
                    shown,
                    shape.Canvas,
                    shape.Mask,
            masks,
                    &self.mSDFShading,
                );
            },
        }
    }
    if (entity.GetComponent(TextComponent)) |text_component| {
        try self.mR2D.DrawText(
            engine_context,
            transform_component,
            text_component,
            surface,
            shape.Canvas,
            shape.Mask,
            masks,
            &self.mSDFShading,
        );
    }
}

fn EndRendering(self: *Renderer, stats: *RenderStats, engine_context: *EngineContext, compute_texture: *ComputeOutput, rendering_mode: RenderingMode) !void {
    const zone = Tracy.ZoneInit("Renderer::EndRendering", @src());
    defer zone.Deinit();

    //recorded into the frame's command buffer along with every other render this frame, and the present after them
    const cmd = self.mPlatform.GetFrameCmdBuff();

    self.mPlatform.PushDebugGroup("End Rendering");
    defer self.mPlatform.PopDebugGroup();

    //a layer with nothing in it skips its pass, and the other pass is told what it would have done
    const plan = PassPlan.Init(
        rendering_mode != .Game,
        rendering_mode != .Overlay,
        self.mR2D.GetShapeCount(.OverlayPipeline),
        self.mR2D.GetShapeCount(.GamePipeline),
    );

    if (plan.ClearTo != .None) {
        self.mPlatform.PushDebugGroup("Clear");
        defer self.mPlatform.PopDebugGroup();
        compute_texture.Clear(engine_context, if (plan.ClearTo == .GameBackground) PushConstants.GAME_BACKGROUND else PushConstants.OVERLAY_BACKGROUND);
        return;
    }

    //everything this render reads, copied up front in one copy pass, before either compute pass reads any of it: the
    //render targets its quads show, as they were last drawn, into the slots they sample, then its shapes and
    //shadings. The shadings are shared by both passes, so they go up once. Uploading between the passes instead would
    //make the second upload wait for the first pass to finish reading
    {
        self.mPlatform.PushDebugGroup("Upload Buffers");
        defer self.mPlatform.PopDebugGroup();
        const copy_pass = self.mPlatform.BeginCopyPass();
        defer self.mPlatform.EndCopyPass(copy_pass);

        for (self.mShownCopies.items) |shown| self.mTextureManager.CopyFromTexture(copy_pass, shown.Source, shown.Handle, shown.Width, shown.Height);
        if (plan.Overlay) try self.mR2D.SetBuffers(stats, engine_context, copy_pass, .OverlayPipeline);
        if (plan.Game) try self.mR2D.SetBuffers(stats, engine_context, copy_pass, .GamePipeline);
        try self.mSDFShading.SetBuffers(engine_context, copy_pass);
    }

    //====================first overlay render pipeline======================================
    if (plan.Overlay) {
        self.mPlatform.PushDebugGroup("Draw - Overlay");
        defer self.mPlatform.PopDebugGroup();

        const overlay_compute_pass = compute_texture.BeginComputePass(engine_context, true);

        //the lean compile unless this pass has merges or marched shapes. Its shapes are sorted by now, so the direct count
        //is right
        self.mOverlayPipeline.Bind(overlay_compute_pass, PassPlan.VariantFor(
            self.mR2D.GetMergeCount(.OverlayPipeline),
            self.mR2D.GetShapeCount(.OverlayPipeline),
            self.mR2D.GetDirectCount(.OverlayPipeline),
        ));
        self.mR2D.BindBuffers(overlay_compute_pass, .OverlayPipeline);
        self.mSDFShading.BindBuffers(overlay_compute_pass);
        self.mTextureManager.BindCompute(overlay_compute_pass);

        //a copy, since the game pass below still needs the camera's own far distance. the canvas
        //always sits CANVAS_DISTANCE out, so the overlay can't depend on how far the game camera sees
        var overlay_push_constants = self.mSDFPushConstants;
        overlay_push_constants.mPerspectiveFar = OverlayCanvas.FAR_DISTANCE;
        overlay_push_constants.mShapesCount = self.mR2D.GetShapeCount(.OverlayPipeline);
        overlay_push_constants.mDirectCount = self.mR2D.GetDirectCount(.OverlayPipeline);
        overlay_push_constants.mFlags = if (plan.OverlayOnGameBackground) PushConstants.FLAG_GAME_BACKGROUND else 0;
        self.mOverlayPipeline.PushUniforms(cmd, overlay_push_constants);

        self.mOverlayPipeline.Dispatch(overlay_compute_pass, @intCast(compute_texture.GetWidth()), @intCast(compute_texture.GetHeight()));
        compute_texture.EndComputePass(overlay_compute_pass);
    }

    //====================then the game layer, under what the overlay drew======================================
    if (plan.Game) {
        self.mPlatform.PushDebugGroup("Draw - Game");
        defer self.mPlatform.PopDebugGroup();

        //under an overlay it reads what that pass wrote, so the texture can't be swapped for a fresh one
        const game_compute_pass = compute_texture.BeginComputePass(engine_context, !plan.GameUnderOverlay);

        self.mGamePipeline.Bind(game_compute_pass, PassPlan.VariantFor(
            self.mR2D.GetMergeCount(.GamePipeline),
            self.mR2D.GetShapeCount(.GamePipeline),
            self.mR2D.GetDirectCount(.GamePipeline),
        ));
        self.mR2D.BindBuffers(game_compute_pass, .GamePipeline);
        self.mSDFShading.BindBuffers(game_compute_pass);
        self.mTextureManager.BindCompute(game_compute_pass);

        self.mSDFPushConstants.mShapesCount = self.mR2D.GetShapeCount(.GamePipeline);
        self.mSDFPushConstants.mDirectCount = self.mR2D.GetDirectCount(.GamePipeline);
        self.mSDFPushConstants.mFlags = if (plan.GameUnderOverlay) PushConstants.FLAG_UNDER_OVERLAY else 0;
        self.mGamePipeline.PushUniforms(cmd, self.mSDFPushConstants);

        self.mGamePipeline.Dispatch(game_compute_pass, @intCast(compute_texture.GetWidth()), @intCast(compute_texture.GetHeight()));
        compute_texture.EndComputePass(game_compute_pass);
    }
}
