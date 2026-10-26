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
const Quat = MathTypes.Quat;

const Entity = @import("../ECSObjects/Entity.zig");
const EntityComponents = @import("../ECSComponents/EComponents.zig");
const TransformComponent = EntityComponents.TransformComponent;
const ViewpointComponent = EntityComponents.ViewpointComponent;
const ShapeComponent = EntityComponents.ShapeComponent;
const SurfaceComponent = EntityComponents.SurfaceComponent;
const TextComponent = EntityComponents.TextComponent;
const ColliderComponent = EntityComponents.ColliderComponent;
const LayoutHiddenTag = EntityComponents.LayoutHiddenTag;
const MaskComponent = EntityComponents.MaskComponent;
const WorldBVH = @import("../Core/WorldBVH.zig");
const SDFProgram = @import("SDFProgram.zig");
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
const BVHDump = @import("BVHDump.zig");
pub const HeatMetric = @import("SDFRayMarcher.zig").HeatMetric;
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

//TODO: a project and run setting the developer and the player can pick (the editor's menu switches vsync for now)
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
    FarDistance: f32, //game layer shapes past this aren't drawn (overlay uses OverlayFarDistance)
    DisplayScale: f32, //the OS display scale, what ConstantPixelSize overlays size by

    /// How far the overlay pass traces through this view, the renderer and picking alike
    pub fn OverlayFarDistance(self: CameraView) f32 {
        const aspect = if (self.TargetHeight > 0) self.TargetWidth / self.TargetHeight else 1;
        return OverlayCanvas.FarDistance(self.TanHalfFov * aspect, self.TanHalfFov);
    }

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
    /// a solid box, its Size its half extents. A solid has an inside, so a ray through a see-through one is drawn
    /// where it goes in and again where it comes out, where a plate is one surface
    Box,
    /// a solid sphere, its radius in each of Size's components, so its box is its bounds
    Sphere,
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
        tex_options: *const Texture2D.TexOptions,
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
    /// AddSurface for a texture manager slot that isn't a Texture2D asset: a render target shown on a quad. A render
    /// target's rows run top down (its rays start at the top left pixel), where a loaded texture's run bottom up, so v
    /// is turned over for it to show the right way up
    pub fn AddSurfaceSlot(
        self: *ShadingBuffers,
        engine_allocator: std.mem.Allocator,
        tex_options: *const Texture2D.TexOptions,
        texture_handle: u32,
        width: usize,
        height: usize,
    ) !usize {
        try self.mSurfShadingBuffBase.append(engine_allocator, .{
            .Color = tex_options.mColor.ToArray(),
            .TextureUV0 = .{ tex_options.mTextureUV0.x, 1 - tex_options.mTextureUV0.y },
            .TextureUV1 = .{ tex_options.mTextureUV1.x, 1 - tex_options.mTextureUV1.y },
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
/// How frames reach the window: vsync until something switches it (SetPresentMode)
mPresentMode: RenderPlatform.PresentMode = .VSync,
/// The shader heatmap: which count of each pixel's work every pass draws instead of the picture, null for the picture.
/// The editor's debug view (Editor > Shader Heatmap)
mHeatmap: ?HeatMetric = null,
/// Draws every collider as well, see-through with its edges marked (Renderer2D.DrawCollider). The editor's debug view
/// (Editor > Show Colliders)
mShowColliders: bool = false,
/// Writes the next overlay pass's camera, shapes and BVH to a file (BVHDump), then goes back off. The editor's debug
/// dump (F7), set just before the render it wants
mDumpOverlayBVH: bool = false,
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
/// The world's screen space this render's overlay shapes are in (FillFromTree), which the overlay pass looks at from
/// the camera as seen from there (OverlayPushConstants). Null when they were placed in world space (FillView)
mOverlayCanvas: ?OverlayCanvas.CanvasTransform = null,

pub fn Init(self: *Renderer, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("Renderer::Init", @src());
    defer zone.Deinit();
    self.mPlatform.Init(engine_context);
    //a claimed window starts out with vsync, but the swapchain is set to it here anyway, so mPresentMode is always
    //what the window really does
    _ = self.SetPresentMode(engine_context, self.mPresentMode);

    try self.mTextureManager.Init(engine_context, 1_000_000_000);

    try self.mGamePipeline.Init(engine_context);
    try self.mOverlayPipeline.Init(engine_context);

    try self.mR2D.Init(engine_context);
    self.mR3D.Init();

    try self.mSDFShading.Init(engine_context);
}

/// Switches vsync on or off, between frames only. A driver that can't turn it off leaves it on, and mPresentMode stays
/// what the window really does
pub fn SetPresentMode(self: *Renderer, engine_context: *EngineContext, present_mode: RenderPlatform.PresentMode) bool {
    if (!self.mPlatform.SetPresentMode(&engine_context.mAppWindow, present_mode)) return false;
    self.mPresentMode = present_mode;
    return true;
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
pub fn BuildPushConstants(transform_component: *const TransformComponent, viewpoint_component: *const ViewpointComponent) PushConstants {
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
        .mHeatMetric = 0,
        .mHeatRedAt = 1,
        .mMediumScale = 1,
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
    try self.Render(engine_context, world_manager, view_scenes, camera_view, stats, push_constants, compute_texture, rendering_mode);
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
    try self.Render(engine_context, scene.mManager, view_scenes, camera_view, stats, push_constants, compute_texture, rendering_mode);
}

fn Render(self: *Renderer, engine_context: *EngineContext, world: *WorldManager, view_scenes: ViewScenes, camera_view: CameraView, stats: *RenderStats, push_constants: PushConstants, compute_texture: *ComputeOutput, rendering_mode: RenderingMode) !void {
    self.mSDFPushConstants = push_constants;
    try self.FillFromTree(engine_context, world, view_scenes, camera_view, stats);
    self.mSDFShading.AddStats(stats);
    try self.EndRendering(stats, engine_context, compute_texture, rendering_mode);
}

/// Fills both passes' shapes from the world's trees (WorldBVH), refit to where everything is this frame: one shape for
/// each of a layer's tree items, in the tree's order, so the tree's own nodes are the pass's BVH. A layer the view
/// shows none of is left empty, so its pass is skipped. Every shape is in its tree's units: the overlay's in the world's
/// screen space (canvas units), which the overlay pass looks at from the camera as seen from there (OverlayPushConstants)
pub fn FillFromTree(self: *Renderer, engine_context: *EngineContext, world: *WorldManager, view_scenes: ViewScenes, camera_view: CameraView, stats: *RenderStats) !void {
    const zone = Tracy.ZoneInit("Renderer::FillFromTree", @src());
    defer zone.Deinit();
    try self.BeginRendering(engine_context.EngineAllocator());

    const bvh = &world.mBVH;
    const canvas = ShapeGeometry.WorldCanvas(world, camera_view);
    self.mOverlayCanvas = canvas;
    const colliders: ?Renderer2D.ColliderShadings = if (self.mShowColliders) try Renderer2D.AddColliderShadings(engine_context, &self.mSDFShading) else null;

    const game_scenes: u64 = switch (view_scenes.Game) {
        .All => std.math.maxInt(u64),
        .One => |scene_id| bvh.SceneBits(&.{scene_id}),
        .None => 0,
    };
    try self.FillLayer(engine_context, world, bvh.Tree(.OverlayLayer), &self.mR2D.mOverlayData, bvh.SceneBits(view_scenes.Overlays), CanvasCameraView(camera_view, canvas), colliders, stats);
    try self.FillLayer(engine_context, world, bvh.Tree(.GameLayer), &self.mR2D.mGameData, game_scenes, camera_view, colliders, stats);
}

/// One layer's shapes for this render, one for each of `tree`'s items. An item with nothing to draw (hidden or gone since
/// the tree was built, in a scene the view doesn't show, a text's click box, a see-through quad, cut off by its mask)
/// is a shape a ray never hits (RenderBuffers.AddNone), so every other item keeps its place in the tree's leaves. `view`
/// is the camera in the tree's units, which only a collider's edge band reads
fn FillLayer(self: *Renderer, engine_context: *EngineContext, world: *WorldManager, tree: *const WorldBVH.LayerTree, buffers: *Renderer2D.RenderBuffers, scenes: u64, view: CameraView, colliders: ?Renderer2D.ColliderShadings, stats: *RenderStats) !void {
    if (scenes == 0) return;
    const frame_allocator = engine_context.FrameAllocator();
    const engine_allocator = engine_context.EngineAllocator();
    const items = tree.mItems.items;

    //which items are drawn and the masks they're cut by, all found first: the masks' programs go in ahead of every merge's
    var masks: ShapeGeometry.ViewMasks = .{};
    var mask_finder = ShapeGeometry.MaskFinder{ .mAllocator = frame_allocator, .mMasks = &masks };
    const drawn = try frame_allocator.alloc(bool, items.len);
    const item_masks = try frame_allocator.alloc(u32, items.len);
    for (items, drawn, item_masks) |item, *draws, *mask| {
        draws.* = Draws(world, item, scenes, colliders != null);
        mask.* = if (draws.*) try ItemMask(world, &mask_finder, item) else SDFProgram.NO_MASK;
    }
    try buffers.SetMasks(engine_allocator, &masks);

    //each text's fill, added the first time one of its letters is drawn
    var text_fills: std.AutoHashMapUnmanaged(Entity.Type, Renderer2D.TextFill) = .empty;
    for (items, drawn, item_masks) |item, draws, mask| {
        const before = buffers.mShapeBufferBase.items.len;
        if (draws) try self.DrawItem(engine_context, world, buffers, item, mask, &masks, &text_fills, view, colliders);
        if (buffers.mShapeBufferBase.items.len == before) {
            try buffers.AddNone(engine_allocator);
        } else {
            stats.TotalObjects += 1;
        }
        std.debug.assert(buffers.mShapeBufferBase.items.len == before + 1);
    }
    try buffers.FinishTree(engine_allocator, frame_allocator, tree);
}

/// The mask a tree item is cut by: its mask region's, found at the build (WorldItem.MaskRegion), so its letters don't
/// each look up their parents again. Found again from where it is now if that region has gone or stopped being one
/// since. Colliders have none, the same as raycasts against them
fn ItemMask(world: *WorldManager, mask_finder: *ShapeGeometry.MaskFinder, item: WorldBVH.WorldItem) !u32 {
    if (item.MaskRegion == Entity.NullObject) return SDFProgram.NO_MASK;
    const region = world.GetEntity(item.MaskRegion);
    if (!region.IsActive() or !region.HasComponent(MaskComponent)) return mask_finder.MaskOf(world.GetEntity(item.Entity), null);
    return mask_finder.RegionMask(region, null);
}

/// Whether a tree item can be drawn this render: in a scene the view shows, still there and not folded away, and a
/// kind that is drawn. A collider only while colliders are shown
fn Draws(world: *WorldManager, item: WorldBVH.WorldItem, scenes: u64, show_colliders: bool) bool {
    if (scenes & (@as(u64, 1) << @intCast(item.SceneSlot)) == 0) return false;
    const entity = world.GetEntity(item.Entity);
    if (!entity.IsActive() or entity.HasComponent(LayoutHiddenTag)) return false;
    return switch (item.Kind) {
        .Quad, .Glyph, .Merge => true,
        .Collider => show_colliders,
        //clicked, never drawn: its letters are
        .Text => false,
    };
}

/// Draws one tree item, in its tree's units (no canvas). Adds at most one shape, none for one with nothing to draw
fn DrawItem(self: *Renderer, engine_context: *EngineContext, world: *WorldManager, buffers: *Renderer2D.RenderBuffers, item: WorldBVH.WorldItem, mask: u32, masks: *const ShapeGeometry.ViewMasks, text_fills: *std.AutoHashMapUnmanaged(Entity.Type, Renderer2D.TextFill), view: CameraView, colliders: ?Renderer2D.ColliderShadings) !void {
    const entity = world.GetEntity(item.Entity);
    switch (item.Kind) {
        //drawn as one shape for all its parts, whether its root has a shape, a surface or a transform or not
        .Merge => try self.mR2D.DrawMerge(buffers, engine_context, entity, null, mask, masks, &self.mSDFShading),
        .Quad => {
            const transform = entity.GetComponent(TransformComponent) orelse return;
            const surface = entity.GetComponent(SurfaceComponent) orelse return;
            if (!surface.mShouldRender) return;
            const quad = ShapeGeometry.QuadOf(entity) orelse return;
            try self.DrawEntityQuad(buffers, engine_context, entity, transform, quad.*, surface, null, mask, masks);
        },
        .Glyph => {
            const transform = entity.GetComponent(TransformComponent) orelse return;
            const surface = entity.GetComponent(SurfaceComponent) orelse return;
            if (!surface.mShouldRender) return;
            const text = entity.GetComponent(TextComponent) orelse return;
            const fill = try text_fills.getOrPut(engine_context.FrameAllocator(), entity.mID);
            if (!fill.found_existing) fill.value_ptr.* = try Renderer2D.TextFill.Of(engine_context, text, surface, &self.mSDFShading);
            //laid out when the tree was built, placed where the text is now
            const params = ShapeGeometry.GetTextParams(transform, text);
            try self.mR2D.DrawGlyph(buffers, engine_context, transform, params, world.mBVH.mGlyphs.items[item.Index], fill.value_ptr.*, null, mask, masks, &self.mSDFShading);
        },
        .Collider => {
            const transform = entity.GetComponent(TransformComponent) orelse return;
            const collider = entity.GetComponent(ColliderComponent) orelse return;
            try self.mR2D.DrawCollider(buffers, engine_context, transform, collider, null, view, colliders.?);
        },
        .Text => {},
    }
}

/// `camera_view` as seen from the world's screen space (`canvas`), where the overlay's shapes are: what the overlay pass
/// looks through. The canvas is turned the camera's way and sits straight in front of it, so this camera is always
/// unturned, CANVAS_DISTANCE / Scale back along the canvas's z, and every distance is the world one over the scale
pub fn CanvasCameraView(camera_view: CameraView, canvas: OverlayCanvas.CanvasTransform) CameraView {
    var view = camera_view;
    view.Pose = .{
        .Position = canvas.ToCanvasPoint(camera_view.Pose.Position),
        .Rotation = canvas.Rotation.Conjugate().MulQuat(camera_view.Pose.Rotation),
    };
    view.FarDistance = camera_view.FarDistance / canvas.Scale;
    return view;
}

/// The overlay pass's push constants from the render's: its own far distance, since the canvas always sits
/// CANVAS_DISTANCE out whatever the game camera sees, and with its shapes in canvas units (a render filled from the
/// tree, `canvas` set) the camera as seen from there (CanvasCameraView). The ray offset is the view's top left corner
/// one unit out, which is how far its corner rays go, and the same seen from the canvas
pub fn OverlayPushConstants(push_constants: PushConstants, canvas: ?OverlayCanvas.CanvasTransform) PushConstants {
    var overlay = push_constants;
    overlay.mPerspectiveFar = OverlayCanvas.FarDistance(@abs(push_constants.mRayOffset[0]), @abs(push_constants.mRayOffset[1]));
    if (canvas) |c| {
        overlay.mPosition = c.ToCanvasPoint(Vec3(f32).FromArray(push_constants.mPosition)).ToArray();
        overlay.mRotation = c.Rotation.Conjugate().MulQuat(Quat(f32).FromArray(push_constants.mRotation)).ToArray();
        overlay.mPerspectiveFar /= c.Scale;
        overlay.mMediumScale = c.Scale;
    }
    return overlay;
}

/// FillFromTree the old way, with no tree: what the view shows gathered (ShapeGeometry.GatherViewShapes) and each
/// shape placed in front of its camera one at a time, the overlay's in world space, then found by testing them all.
/// What FillFromTree is checked against in the tests. Never called by the engine, so it isn't compiled into it
pub fn FillView(self: *Renderer, engine_context: *EngineContext, world: *WorldManager, view_scenes: ViewScenes, camera_view: CameraView, stats: *RenderStats) !void {
    const engine_allocator = engine_context.EngineAllocator();
    const frame_allocator = engine_context.FrameAllocator();
    try self.BeginRendering(engine_allocator);
    self.mOverlayCanvas = null;

    const view = try ShapeGeometry.GatherViewShapes(frame_allocator, world, camera_view, view_scenes, ShapeGeometry.VISUALS_QUERY);
    try self.mR2D.mOverlayData.SetMasks(engine_allocator, &view.Masks);
    try self.mR2D.mGameData.SetMasks(engine_allocator, &view.Masks);
    stats.TotalObjects += view.Shapes.items.len;
    for (view.Shapes.items) |shape| try self.DrawShape(engine_context, shape, &view.Masks);

    if (self.mShowColliders) {
        const colliders = try ShapeGeometry.GatherViewShapes(frame_allocator, world, camera_view, view_scenes, .{ .Component = ColliderComponent });
        const shadings = try Renderer2D.AddColliderShadings(engine_context, &self.mSDFShading);
        for (colliders.Shapes.items) |shape| {
            const transform_component = shape.Entity.GetComponent(TransformComponent) orelse continue;
            const collider = shape.Entity.GetComponent(ColliderComponent).?;
            try self.mR2D.DrawCollider(self.ViewBuffers(shape.Canvas), engine_context, transform_component, collider, shape.Canvas, camera_view, shadings);
        }
    }
    self.mR2D.mOverlayData.FinishView();
    self.mR2D.mGameData.FinishView();
}

/// The pass a gathered shape is drawn in: the overlay's when it has a canvas
fn ViewBuffers(self: *Renderer, canvas: ?OverlayCanvas.CanvasTransform) *Renderer2D.RenderBuffers {
    return if (canvas != null) &self.mR2D.mOverlayData else &self.mR2D.mGameData;
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

/// One gathered shape (FillView), placed by its canvas
fn DrawShape(self: *Renderer, engine_context: *EngineContext, shape: ShapeGeometry.ViewShape, masks: *const ShapeGeometry.ViewMasks) anyerror!void {
    const entity = shape.Entity;
    const buffers = self.ViewBuffers(shape.Canvas);
    //a merge is drawn as one shape for all its parts, whether its root has a shape, a surface or a transform or not
    if (shape.Merge) return self.mR2D.DrawMerge(buffers, engine_context, entity, shape.Canvas, shape.Mask, masks, &self.mSDFShading);
    const transform_component = entity.GetComponent(TransformComponent).?;

    //a surface paints whatever the entity has, its shape or its text. a hidden one is skipped here and by picking
    //alike, so nothing can be clicked that isn't drawn
    const surface = entity.GetComponent(SurfaceComponent) orelse return;
    if (!surface.mShouldRender) return;

    if (ShapeGeometry.QuadOf(entity)) |quad| try self.DrawEntityQuad(buffers, engine_context, entity, transform_component, quad.*, surface, shape.Canvas, shape.Mask, masks);
    if (entity.GetComponent(TextComponent)) |text_component| {
        try self.mR2D.DrawText(buffers, engine_context, transform_component, text_component, surface, shape.Canvas, shape.Mask, masks, &self.mSDFShading);
    }
}

/// An entity's quad: the render target it shows in place of its texture when it is a viewport (ViewportComponent)
fn DrawEntityQuad(self: *Renderer, buffers: *Renderer2D.RenderBuffers, engine_context: *EngineContext, entity: Entity, transform: *const TransformComponent, quad: ShapeComponent.Quad, surface: *const SurfaceComponent, canvas: ?OverlayCanvas.CanvasTransform, mask: u32, masks: *const ShapeGeometry.ViewMasks) !void {
    //a quad showing a player's view samples its render target instead of its texture
    const shown = if (entity.GetComponent(ViewportComponent)) |viewport| try Viewports.ShownTarget(engine_context, viewport.*) else null;
    if (shown) |target| try self.mShownCopies.append(engine_context.EngineAllocator(), target);
    try self.mR2D.DrawQuad(buffers, engine_context, transform, quad, surface, shown, canvas, mask, masks, &self.mSDFShading);
}

/// Which compile of the shader a pass runs: the heatmap one while it's shown, otherwise the lean one unless the pass has
/// merges or marched shapes. Only right once the pass's shapes are sorted (SetBuffers), for the direct count
fn PassVariant(self: *const Renderer, pipeline_kind: RenderPipeline.PipelineType) PassPlan.ShaderVariant {
    if (self.mHeatmap != null) return .Heatmap;
    return PassPlan.VariantFor(
        self.mR2D.GetMergeCount(pipeline_kind),
        self.mR2D.GetShapeCount(pipeline_kind),
        self.mR2D.GetDirectCount(pipeline_kind),
    );
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

    //what the heatmap colors by, read only by its compile. Set before the overlay pass copies the push constants
    if (self.mHeatmap) |metric| {
        self.mSDFPushConstants.mHeatMetric = @intFromEnum(metric);
        self.mSDFPushConstants.mHeatRedAt = @floatFromInt(metric.RedAt());
    }

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

        self.mOverlayPipeline.Bind(overlay_compute_pass, self.PassVariant(.OverlayPipeline));
        self.mR2D.BindBuffers(overlay_compute_pass, .OverlayPipeline);
        self.mSDFShading.BindBuffers(overlay_compute_pass);
        self.mTextureManager.BindCompute(overlay_compute_pass);

        //a copy, since the game pass below still needs the camera itself
        var overlay_push_constants = OverlayPushConstants(self.mSDFPushConstants, self.mOverlayCanvas);
        overlay_push_constants.mShapesCount = self.mR2D.GetShapeCount(.OverlayPipeline);
        overlay_push_constants.mDirectCount = self.mR2D.GetDirectCount(.OverlayPipeline);
        overlay_push_constants.mFlags = if (plan.OverlayOnGameBackground) PushConstants.FLAG_GAME_BACKGROUND else 0;
        self.mOverlayPipeline.PushUniforms(cmd, overlay_push_constants);
        if (self.mDumpOverlayBVH) {
            self.mDumpOverlayBVH = false;
            const buffers = &self.mR2D.mOverlayData;
            if (BVHDump.Write(engine_context, .{
                .Camera = overlay_push_constants,
                .Shapes = buffers.mShapeBufferBase.items,
                .Nodes = buffers.mBVHNodes.items,
            })) {
                std.log.info("Wrote the overlay pass's BVH to {s}", .{BVHDump.FILE_NAME});
            } else |err| {
                std.log.warn("Couldn't write the BVH dump: {t}", .{err});
            }
        }

        self.mOverlayPipeline.Dispatch(overlay_compute_pass, @intCast(compute_texture.GetWidth()), @intCast(compute_texture.GetHeight()));
        compute_texture.EndComputePass(overlay_compute_pass);
    }

    //====================then the game layer, under what the overlay drew======================================
    if (plan.Game) {
        self.mPlatform.PushDebugGroup("Draw - Game");
        defer self.mPlatform.PopDebugGroup();

        //under an overlay it reads what that pass wrote, so the texture can't be swapped for a fresh one
        const game_compute_pass = compute_texture.BeginComputePass(engine_context, !plan.GameUnderOverlay);

        self.mGamePipeline.Bind(game_compute_pass, self.PassVariant(.GamePipeline));
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
