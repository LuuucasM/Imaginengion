const std = @import("std");
const RenderTargetComponent = @import("../ECSComponents/Shared/RenderTargetComponent.zig");
const builtin = @import("builtin");
const SSBO = @import("../SSBOs/SSBO.zig");
const sdl = @import("../Core/CImports.zig").sdl;
const VertexArray = @import("../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const UniformBuffer = @import("../UniformBuffers/UniformBuffer.zig");
const AssetHandle = @import("../ECSObjects/AssetHandle.zig");
const IndexBuffer = @import("../IndexBuffers/IndexBuffer.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const RenderStats = @import("../Core/EngineStats.zig").RenderStats;
const PipelineType = @import("RenderPipeline.zig").PipelineType;
const ShadingBuffers = @import("Renderer.zig").ShadingBuffers;
const ShapeType = @import("Renderer.zig").ShapeType;
const GPUAsserts = @import("../Core/GPUAsserts.zig");

const Assets = @import("../ECSComponents/AComponents.zig");
const Texture2D = Assets.Texture2D;
const TextAsset = Assets.TextAsset;

const MathTypes = @import("../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;
const Vec4 = MathTypes.Vec4;
const Quat = MathTypes.Quat;
const Mat4 = MathTypes.Mat4;

const SDFFunctions = @import("../Math/SDFFunctions.zig");
const THICKNESS_2D = SDFFunctions.THICKNESS_2D;
const Aabb = @import("../Math/Aabb.zig");

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const EntityTransformComponent = EntityComponents.TransformComponent;
const ShapeComponent = EntityComponents.ShapeComponent;
const SurfaceComponent = EntityComponents.SurfaceComponent;
const TextComponent = EntityComponents.TextComponent;
const ColliderComponent = EntityComponents.ColliderComponent;
const CameraView = @import("Renderer.zig").CameraView;

const StorageBufferBinding = @import("RenderPlatform.zig").StorageBufferBinding;
const TextLayout = @import("TextLayout.zig");
const CanvasTransform = @import("../Math/OverlayCanvas.zig").CanvasTransform;
const ShapeGeometry = @import("ShapeGeometry.zig");
const WorldBVH = @import("../Core/WorldBVH.zig");
const BVH = @import("../Core/BVH.zig");
const SDFProgram = @import("SDFProgram.zig");
const SDFCompiler = @import("SDFCompiler.zig");
const Entity = @import("../ECSObjects/Entity.zig");

const Tracy = @import("../Core/Tracy.zig");

const Renderer2D = @This();

const MAX_PATH_LEN = 256;

const is_spirv = builtin.target.cpu.arch.isSpirV();

const ResetOptions = enum {
    ClearAndFree,
    ClearRetainingCapacity,
};

/// One shape as the marcher finds it: everything every step of the search reads, the same layout for every kind of
/// shape. What is only needed once a shape is the one hit lives in its ShapeSurface, so the search reads less per shape
pub const ShapeData = extern struct {
    /// The ray checks how see-through the surface it hits is, and if it is at all, goes on to what is behind it.
    /// Without it a surface hides what is behind it whatever its alpha
    pub const FLAG_TRANSPARENT: u32 = 1 << 0;

    //where the shape is and how it is turned, as the move from world space into the shape's own space, where it is axis
    //aligned and centered on the origin: the shape's own x, y and z axes in world space, each with -dot(axis, center)
    //in w. A world point's coordinate along one is dot(axis.xyz, point) + axis.w, and a direction's dot(axis.xyz, dir).
    //Worked out once on the CPU (ShapeAxes) rather than rotating by a quaternion for every ray test. For a glyph the
    //center is its box's center, not the pen position it was laid out from
    AxisX: if (is_spirv) Vec4(f32).VectorT else Vec4(f32).ArrayT,
    AxisY: if (is_spirv) Vec4(f32).VectorT else Vec4(f32).ArrayT,
    AxisZ: if (is_spirv) Vec4(f32).VectorT else Vec4(f32).ArrayT,
    //half extents for the box shapes, quads and glyphs, including their THICKNESS_2D depth
    Size: if (is_spirv) Vec3(f32).VectorT else Vec3(f32).ArrayT,
    //what Type says. A quad's corner radii: world units, already scaled and clamped to at most half the smaller
    //side, in SDFFunctions' order (x top right, y bottom right, z top left, w bottom left). Unused (0) for a glyph
    Params: if (is_spirv) Vec4(f32).VectorT else Vec4(f32).ArrayT align(16),
    Type: ShapeType,
    //the mask it is cut by (SDFProgram.MaskData), which is cut by the masks around it in turn. SDFProgram.NO_MASK for none
    MaskIndex: u32,
    //its ShapeSurface
    SurfaceIndex: u32,
    //the FLAG_ bits: behavior the developer turns on per shape that costs extra checks. A shape without a flag never
    //pays for what it turns on. Never set on their own, only from what the shape's component asks for
    Flags: u32,
};

/// The AxisX, AxisY and AxisZ of a shape centered at `center` and turned by `rotation`: its own axes in world space,
/// each with -dot(axis, center) in w (see ShapeData)
pub fn ShapeAxes(center: Vec3(f32), rotation: Quat(f32)) [3]Vec4(f32).ArrayT {
    var axes: [3]Vec4(f32).ArrayT = undefined;
    for (rotation.Axes(), &axes) |world_axis, *axis| {
        axis.* = .{ world_axis.x, world_axis.y, world_axis.z, -world_axis.Dot(center) };
    }
    return axes;
}

/// What only the shape that was hit needs: which surfaces it is shaded with. The same slots for every kind of shape,
/// read the way its Type says
pub const ShapeSurface = extern struct {
    //what a hit on the shape is painted with: a quad's surface, a glyph's text fill (its color and texture)
    ShadingHandle: u32,
    //a quad's border band's solid color surface, drawn instead of ShadingHandle's within BorderWidth of its edge. A
    //solid's band is along a box's edges or round a sphere's outline (SDFFunctions.InIMBoxEdge, InIMSphereRim).
    //ShadingHandle again for a shape without a border
    BorderShadingHandle: u32,
    //a quad's border: world units, already scaled and kept to at most half the smaller side. 0 for none
    BorderWidth: f32,
    //a glyph's atlas entry: where its letter is in the font atlas, shared by every glyph of that letter
    //(ShadingBuffers.GlyphSurface). Unused by other shapes
    AtlasHandle: u32 = 0,
};

comptime {
    GPUAsserts.AssertGPULayout(ShapeData);
    GPUAsserts.AssertGPULayout(ShapeSurface);
}

pub const RenderBuffers = struct {
    mShapeBuffer: SSBO = .{},
    mShapeBufferBase: std.ArrayList(ShapeData) = .empty,

    mSurfaceBuffer: SSBO = .{},
    mSurfaceBufferBase: std.ArrayList(ShapeSurface) = .empty,

    /// The view's masks (ShapeGeometry.ViewMasks), shared by every shape under each. Uploaded as they are: a shape's
    /// MaskIndex is into them
    mMaskBuffer: SSBO = .{},
    mMaskBufferBase: std.ArrayList(SDFProgram.MaskData) = .empty,
    /// Every program this batch runs: the masks' first, as the view made them, then each merge's (DrawMerge)
    mPrograms: SDFCompiler.Programs = .{},
    mInstrBuffer: SSBO = .{},
    mPartBuffer: SSBO = .{},

    /// How many of the shapes, from the front, are found with a ray test straight against them; the rest are marched.
    /// Every shape is direct for now. Set by FinishTree or FinishView
    mDirectCount: u32 = 0,

    /// The BVH over the direct shapes: the world's tree for this layer (FinishTree), whose leaves' items are runs of the
    /// shapes, since they were added in its order. Empty for a view filled the old way (FinishView)
    mBVHNodes: std.ArrayList(BVH.Node) = .empty,
    /// mBVHNodes on the GPU, uploaded with the shapes. Its node count is the root's Skip, and there is no tree when
    /// there are no direct shapes
    mNodeBuffer: SSBO = .{},

    /// How many of the shapes are quads and how many glyphs, for the stats
    mQuadCount: usize = 0,
    mGlyphCount: usize = 0,
    mMergeCount: usize = 0,

    pub fn Init(self: *RenderBuffers, engine_context: *EngineContext) !void {
        self.mShapeBuffer.Init(engine_context, @sizeOf(ShapeData) * 100, 2, .Compute);
        self.mShapeBufferBase = try std.ArrayList(ShapeData).initCapacity(engine_context.EngineAllocator(), 100);

        self.mSurfaceBuffer.Init(engine_context, @sizeOf(ShapeSurface) * 100, 3, .Compute);
        self.mSurfaceBufferBase = try std.ArrayList(ShapeSurface).initCapacity(engine_context.EngineAllocator(), 100);

        self.mMaskBuffer.Init(engine_context, @sizeOf(SDFProgram.MaskData) * 16, 4, .Compute);

        //a tree over 100 shapes in leaves of up to 4 is around 50 to 70 nodes
        self.mNodeBuffer.Init(engine_context, @sizeOf(BVH.Node) * 64, 5, .Compute);

        //a one shape mask is one instruction and one part
        self.mInstrBuffer.Init(engine_context, @sizeOf(SDFProgram.Instr) * 16, 6, .Compute);
        self.mPartBuffer.Init(engine_context, @sizeOf(SDFProgram.Part) * 16, 7, .Compute);
    }
    pub fn Deinit(self: *RenderBuffers, engine_context: *EngineContext) void {
        self.mShapeBuffer.Deinit(engine_context);
        self.mShapeBufferBase.deinit(engine_context.EngineAllocator());

        self.mSurfaceBuffer.Deinit(engine_context);
        self.mSurfaceBufferBase.deinit(engine_context.EngineAllocator());

        self.mMaskBuffer.Deinit(engine_context);
        self.mMaskBufferBase.deinit(engine_context.EngineAllocator());
        self.mPrograms.Deinit(engine_context.EngineAllocator());
        self.mInstrBuffer.Deinit(engine_context);
        self.mPartBuffer.Deinit(engine_context);

        self.mBVHNodes.deinit(engine_context.EngineAllocator());
        self.mNodeBuffer.Deinit(engine_context);
    }
    pub fn Reset(self: *RenderBuffers, engine_allocator: std.mem.Allocator, reset_options: ResetOptions) void {
        switch (reset_options) {
            .ClearAndFree => {
                self.mShapeBufferBase.clearAndFree(engine_allocator);
                self.mSurfaceBufferBase.clearAndFree(engine_allocator);
                self.mMaskBufferBase.clearAndFree(engine_allocator);
                self.mPrograms.Deinit(engine_allocator);
                self.mPrograms = .{};
                self.mBVHNodes.clearAndFree(engine_allocator);
            },
            .ClearRetainingCapacity => {
                self.mShapeBufferBase.clearRetainingCapacity();
                self.mSurfaceBufferBase.clearRetainingCapacity();
                self.mMaskBufferBase.clearRetainingCapacity();
                self.mPrograms.Clear();
                self.mBVHNodes.clearRetainingCapacity();
            },
        }
        self.mQuadCount = 0;
        self.mGlyphCount = 0;
        self.mMergeCount = 0;
        self.mDirectCount = 0;
    }
    pub fn SetBuffers(self: *RenderBuffers, stats: *RenderStats, engine_context: *EngineContext, copy_pass: *anyopaque) !void {
        const zone = Tracy.ZoneInit("Renderer2D::SetBuffers", @src());
        defer zone.Deinit();

        const shape_byte_size = self.mShapeBufferBase.items.len * @sizeOf(ShapeData);
        _ = self.mShapeBuffer.SetData(engine_context, copy_pass, self.mShapeBufferBase.items.ptr, shape_byte_size, 0);

        const surface_byte_size = self.mSurfaceBufferBase.items.len * @sizeOf(ShapeSurface);
        _ = self.mSurfaceBuffer.SetData(engine_context, copy_pass, self.mSurfaceBufferBase.items.ptr, surface_byte_size, 0);

        //masks and their shapes' programs
        const mask_byte_size = self.mMaskBufferBase.items.len * @sizeOf(SDFProgram.MaskData);
        _ = self.mMaskBuffer.SetData(engine_context, copy_pass, self.mMaskBufferBase.items.ptr, mask_byte_size, 0);
        const instrs = self.mPrograms.mInstrs.items;
        _ = self.mInstrBuffer.SetData(engine_context, copy_pass, instrs.ptr, instrs.len * @sizeOf(SDFProgram.Instr), 0);
        const parts = self.mPrograms.mParts.items;
        _ = self.mPartBuffer.SetData(engine_context, copy_pass, parts.ptr, parts.len * @sizeOf(SDFProgram.Part), 0);

        //the BVH over the direct shapes
        const node_byte_size = self.mBVHNodes.items.len * @sizeOf(BVH.Node);
        _ = self.mNodeBuffer.SetData(engine_context, copy_pass, self.mBVHNodes.items.ptr, node_byte_size, 0);
        //added to stats: the overlay and game passes each have their own quads and glyphs
        stats.OutputQuadNum += self.mQuadCount;
        stats.OutputGlyphNum += self.mGlyphCount;
        stats.OutputMergeNum += self.mMergeCount;
    }
    pub fn BindBuffers(self: RenderBuffers, render_pass: *anyopaque) void {
        self.mShapeBuffer.Bind(render_pass);
        self.mSurfaceBuffer.Bind(render_pass);
        self.mMaskBuffer.Bind(render_pass);
        self.mNodeBuffer.Bind(render_pass);
        self.mInstrBuffer.Bind(render_pass);
        self.mPartBuffer.Bind(render_pass);
    }

    /// The masks every shape added after points into by its MaskIndex (ShapeGeometry.ViewMasks). First, while the
    /// programs are empty, so the masks' program ranges stay right
    pub fn SetMasks(self: *RenderBuffers, engine_allocator: std.mem.Allocator, masks: *const ShapeGeometry.ViewMasks) !void {
        std.debug.assert(self.mPrograms.mInstrs.items.len == 0);
        try self.mMaskBufferBase.appendSlice(engine_allocator, masks.mMasks.items);
        try self.mPrograms.mInstrs.appendSlice(engine_allocator, masks.mPrograms.mInstrs.items);
        try self.mPrograms.mParts.appendSlice(engine_allocator, masks.mPrograms.mParts.items);
        try self.mPrograms.mPartSurfaces.appendSlice(engine_allocator, masks.mPrograms.mPartSurfaces.items);
    }

    /// Adds a shape and its surface, pointing the shape at it. The shape's SurfaceIndex is filled in here
    fn AddShape(self: *RenderBuffers, engine_allocator: std.mem.Allocator, shape: ShapeData, surface: ShapeSurface) !void {
        var added = shape;
        added.SurfaceIndex = @intCast(self.mSurfaceBufferBase.items.len);
        try self.mSurfaceBufferBase.append(engine_allocator, surface);
        try self.mShapeBufferBase.append(engine_allocator, added);
        switch (shape.Type) {
            .Quad => self.mQuadCount += 1,
            .Glyph => self.mGlyphCount += 1,
            .Merge => self.mMergeCount += 1,
            .Box, .Sphere, .None => {},
        }
    }

    /// A shape that is never drawn, which a ray test always misses: a tree item with nothing to draw this render (a
    /// text's click box, a see-through quad, something hidden or in a scene the view doesn't show), so every other
    /// item stays at its place in the tree's leaves
    pub fn AddNone(self: *RenderBuffers, engine_allocator: std.mem.Allocator) !void {
        const zero = [4]f32{ 0, 0, 0, 0 };
        try self.AddShape(engine_allocator, .{
            .AxisX = zero,
            .AxisY = zero,
            .AxisZ = zero,
            .Size = .{ 0, 0, 0 },
            .Params = zero,
            .Type = .None,
            .MaskIndex = SDFProgram.NO_MASK,
            .SurfaceIndex = undefined,
            .Flags = 0,
        }, .{ .ShadingHandle = 0, .BorderShadingHandle = 0, .BorderWidth = 0 });
    }

    /// Done adding one shape for each of `tree`'s items, in its order: the tree's nodes are this layer's BVH, every
    /// shape is direct, and each shape's SurfaceIndex, which is what a tie at exactly the same depth goes by
    /// (SDFRayMarcher.HitOrder), becomes its item's Order, so the tie goes the same way whatever shape the tree is in
    pub fn FinishTree(self: *RenderBuffers, engine_allocator: std.mem.Allocator, frame_allocator: std.mem.Allocator, tree: *const WorldBVH.LayerTree) !void {
        const items = tree.mItems.items;
        std.debug.assert(self.mShapeBufferBase.items.len == items.len);
        const added = try frame_allocator.dupe(ShapeSurface, self.mSurfaceBufferBase.items);
        for (self.mShapeBufferBase.items, items) |*shape, item| {
            self.mSurfaceBufferBase.items[item.Order] = added[shape.SurfaceIndex];
            shape.SurfaceIndex = item.Order;
        }
        try self.mBVHNodes.appendSlice(engine_allocator, tree.mNodes.items);
        self.mDirectCount = @intCast(items.len);
    }

    /// Done adding a view's shapes the old way, one at a time with no tree (Renderer.FillView): every shape direct, found
    /// by testing them all
    pub fn FinishView(self: *RenderBuffers) void {
        self.mDirectCount = @intCast(self.mShapeBufferBase.items.len);
    }
};

mGameData: RenderBuffers = .{},
mOverlayData: RenderBuffers = .{},
/// The merges already warned about being nested too deep to draw, so each is only warned about once
mWarnedMerges: std.AutoHashMapUnmanaged(Entity.Type, void) = .empty,

pub fn Init(self: *Renderer2D, engine_context: *EngineContext) !void {
    try self.mGameData.Init(engine_context);
    try self.mOverlayData.Init(engine_context);
}

pub fn Deinit(self: *Renderer2D, engine_context: *EngineContext) void {
    self.mGameData.Deinit(engine_context);
    self.mOverlayData.Deinit(engine_context);
    self.mWarnedMerges.deinit(engine_context.EngineAllocator());
}

pub fn StartBatch(self: *Renderer2D, engine_allocator: std.mem.Allocator) void {
    self.mGameData.Reset(engine_allocator, .ClearRetainingCapacity);
    self.mOverlayData.Reset(engine_allocator, .ClearRetainingCapacity);
}

pub fn SetBuffers(self: *Renderer2D, stats: *RenderStats, engine_context: *EngineContext, copy_pass: *anyopaque, pipeline_t: PipelineType) !void {
    switch (pipeline_t) {
        .GamePipeline => {
            try self.mGameData.SetBuffers(stats, engine_context, copy_pass);
            stats.GameBVH = stats.GameBVH.Bigger(BVH.Stats(self.mGameData.mBVHNodes.items));
        },
        .OverlayPipeline => {
            try self.mOverlayData.SetBuffers(stats, engine_context, copy_pass);
            stats.OverlayBVH = stats.OverlayBVH.Bigger(BVH.Stats(self.mOverlayData.mBVHNodes.items));
        },
    }
}

pub fn BindBuffers(self: Renderer2D, render_pass: *anyopaque, pipeline_t: PipelineType) void {
    switch (pipeline_t) {
        .GamePipeline => self.mGameData.BindBuffers(render_pass),
        .OverlayPipeline => self.mOverlayData.BindBuffers(render_pass),
    }
}

/// How many shapes a pass has to march past, every kind together
pub fn GetShapeCount(self: Renderer2D, pipeline_kind: PipelineType) u32 {
    return switch (pipeline_kind) {
        .GamePipeline => @intCast(self.mGameData.mShapeBufferBase.items.len),
        .OverlayPipeline => @intCast(self.mOverlayData.mShapeBufferBase.items.len),
    };
}

/// How many of a pass's shapes, from the front of its buffer, are found with a ray test straight against them. The
/// rest are marched. Only right once its SetBuffers has sorted them
pub fn GetDirectCount(self: Renderer2D, pipeline_kind: PipelineType) u32 {
    return switch (pipeline_kind) {
        .GamePipeline => self.mGameData.mDirectCount,
        .OverlayPipeline => self.mOverlayData.mDirectCount,
    };
}

/// How many merges (MergeComponent) a pass draws, which decide whether it needs the full shader (PassPlan.VariantFor)
pub fn GetMergeCount(self: Renderer2D, pipeline_kind: PipelineType) usize {
    return switch (pipeline_kind) {
        .GamePipeline => self.mGameData.mMergeCount,
        .OverlayPipeline => self.mOverlayData.mMergeCount,
    };
}

/// Whether a quad painted with `surface` draws nothing at all: see-through, with a fill and a border (if it has one)
/// both fully see-through. Its texture doesn't matter, since the fill color tints it (SDFRayMarcher.SurfaceColor). Such
/// a quad is only there to be clicked, like a menu row's button until it is hovered, and picking tests its box on the
/// CPU, so it is left out of the shapes. A quad that isn't see-through hides what is behind it whatever its alpha, so
/// it is still drawn
pub fn QuadDrawsNothing(surface: SurfaceComponent) bool {
    if (!surface.mTexOptions.mIsTransparent) return false;
    if (surface.mTexOptions.mColor.w > 0) return false;
    return surface.mBorderWidth <= 0 or surface.mBorderColor.w <= 0;
}

pub fn DrawQuad(
    self: *Renderer2D,
    buffers: *RenderBuffers, //the pass it is drawn in
    engine_context: *EngineContext,
    transform_component: *EntityTransformComponent,
    quad: ShapeComponent.Quad,
    surface: *SurfaceComponent, //what it is painted with
    shown: ?RenderTargetComponent.Shown, //a render target it shows in place of its texture (ViewportComponent)
    canvas: ?CanvasTransform, //set for overlay scenes, whose transforms are in canvas units, and drawn in the overlay pass
    mask: u32, //the mask it is cut by, into `masks`, SDFProgram.NO_MASK for none
    masks: *const ShapeGeometry.ViewMasks,
    shading_buff: *ShadingBuffers,
) !void {
    _ = self;
    //invisible: nothing to draw, and every pixel under it would start a whole new walk past it
    if (QuadDrawsNothing(surface.*)) return;
    //the same box picking tests against
    const box = ShapeGeometry.QuadBox(transform_component, quad, surface.mBorderWidth, canvas);
    //cut off altogether: nothing to draw, and nothing for every pixel to march past
    if (masks.CutsOff(mask, box)) return;

    const texture_asset = try surface.mTexture.GetAsset(engine_context, Texture2D);

    const shading_handle = if (shown) |target|
        try shading_buff.AddSurfaceSlot(engine_context.EngineAllocator(), &surface.mTexOptions, target.Handle, target.Width, target.Height)
    else
        try shading_buff.AddSurface(
            engine_context.EngineAllocator(),
            &surface.mTexOptions,
            texture_asset,
        );

    var shading_flag: u32 = 0;
    if (surface.mTexOptions.mIsTransparent) shading_flag |= ShapeData.FLAG_TRANSPARENT;

    //the border is a solid color: its own surface, which the marcher draws untextured
    var border_shading_handle = shading_handle;
    if (box.BorderWidth > 0) {
        var border_options: Texture2D.TexOptions = .default;
        border_options.mColor = surface.mBorderColor;
        border_shading_handle = try shading_buff.AddSurface(engine_context.EngineAllocator(), &border_options, texture_asset);
        if (surface.mBorderColor.w < 1.0) shading_flag |= ShapeData.FLAG_TRANSPARENT;
    }

    const axes = ShapeAxes(box.Center, box.Rotation);
    try buffers.AddShape(engine_context.EngineAllocator(), .{
        .AxisX = axes[0],
        .AxisY = axes[1],
        .AxisZ = axes[2],
        .Size = box.HalfExtents.ToArray(),
        .Params = box.CornerRadii.ToArray(),
        .Type = .Quad,
        .MaskIndex = mask,
        .SurfaceIndex = undefined,
        .Flags = shading_flag,
    }, .{
        .ShadingHandle = @intCast(shading_handle),
        .BorderShadingHandle = @intCast(border_shading_handle),
        .BorderWidth = box.BorderWidth,
    });
}

/// Draws a merge (MergeComponent) as one shape: compiled into its pass's programs, a plate over the rectangle its parts
/// lie within, where its program says, each part painted with its surface the way a quad is, blended where they meet.
/// Its root's surface, if it has one, gives its border, around the whole merged outline
pub fn DrawMerge(
    self: *Renderer2D,
    buffers: *RenderBuffers, //the pass it is drawn in
    engine_context: *EngineContext,
    root: Entity,
    canvas: ?CanvasTransform, //set for overlay scenes, whose transforms are in canvas units, and drawn in the overlay pass
    mask: u32, //the mask it is cut by, into `masks`, SDFProgram.NO_MASK for none
    masks: *const ShapeGeometry.ViewMasks,
    shading_buff: *ShadingBuffers,
) !void {
    const zone = Tracy.ZoneInit("Renderer2D::DrawMerge", @src());
    defer zone.Deinit();
    const engine_allocator = engine_context.EngineAllocator();

    const compiled = SDFCompiler.Compile(engine_allocator, root, canvas, &buffers.mPrograms) catch |err| switch (err) {
        error.MergeTooDeep => {
            const warned = try self.mWarnedMerges.getOrPut(engine_allocator, root.mID);
            if (!warned.found_existing) std.log.warn("merge on entity {d} isn't drawn: merges subtracted or intersected inside each other need more than {d} stack slots", .{ root.mID, SDFProgram.MAX_STACK });
            return;
        },
        else => return err,
    };
    if (compiled.Parts.Count == 0) return;

    const box = ShapeGeometry.MergeBox(compiled);
    //cut off altogether: nothing to draw, and nothing for every pixel to march past
    if (masks.CutsOff(mask, box)) return;

    //a root with no surface draws with a plain one
    var plain = SurfaceComponent{};
    plain.mTexture.mManager = &engine_context.mAssetManager;
    const surface = root.GetComponent(SurfaceComponent) orelse &plain;
    const texture_asset = try surface.mTexture.GetAsset(engine_context, Texture2D);
    const shading_handle = try shading_buff.AddSurface(engine_allocator, &surface.mTexOptions, texture_asset);

    //each part's shading, from the surface that paints it, added once for every part it paints. See-through where any
    //of them is, the way a quad's surface is
    var shading_flag: u32 = 0;
    var painters: std.AutoHashMapUnmanaged(Entity.Type, u32) = .empty;
    defer painters.deinit(engine_allocator);
    var plain_shading: ?u32 = null;
    const first = compiled.Parts.First;
    for (buffers.mPrograms.mParts.items[first..][0..compiled.Parts.Count], buffers.mPrograms.mPartSurfaces.items[first..][0..compiled.Parts.Count]) |*part, painter| {
        const painter_entity = painter orelse {
            if (plain_shading == null) plain_shading = @intCast(try PlainShading(engine_context, shading_buff, &plain));
            part.Shading = plain_shading.?;
            continue;
        };
        const known = try painters.getOrPut(engine_allocator, painter_entity.mID);
        if (!known.found_existing) {
            const painter_surface = painter_entity.GetComponent(SurfaceComponent).?;
            const painter_texture = try painter_surface.mTexture.GetAsset(engine_context, Texture2D);
            known.value_ptr.* = @intCast(try shading_buff.AddSurface(engine_allocator, &painter_surface.mTexOptions, painter_texture));
            if (painter_surface.mTexOptions.mIsTransparent) shading_flag |= ShapeData.FLAG_TRANSPARENT;
        }
        part.Shading = known.value_ptr.*;
    }

    //the border grows with the root, by its smaller axis, the way a quad's does
    var border_width: f32 = 0;
    var border_shading_handle = shading_handle;
    if (surface.mBorderWidth > 0) {
        const world_scale = if (root.GetComponent(EntityTransformComponent)) |transform| transform.GetWorldScale() else Vec3(f32){ .x = 1, .y = 1, .z = 1 };
        border_width = surface.mBorderWidth * @min(world_scale.x, world_scale.y) * if (canvas) |c| c.Scale else 1.0;
        var border_options: Texture2D.TexOptions = .default;
        border_options.mColor = surface.mBorderColor;
        border_shading_handle = try shading_buff.AddSurface(engine_allocator, &border_options, texture_asset);
        if (surface.mBorderColor.w < 1.0) shading_flag |= ShapeData.FLAG_TRANSPARENT;
    }

    const axes = ShapeAxes(box.Center, box.Rotation);
    try buffers.AddShape(engine_allocator, .{
        .AxisX = axes[0],
        .AxisY = axes[1],
        .AxisZ = axes[2],
        .Size = box.HalfExtents.ToArray(),
        .Params = SDFProgram.MergeParams(compiled.Range),
        .Type = .Merge,
        .MaskIndex = mask,
        .SurfaceIndex = undefined,
        .Flags = shading_flag,
    }, .{
        .ShadingHandle = @intCast(shading_handle),
        .BorderShadingHandle = @intCast(border_shading_handle),
        .BorderWidth = border_width,
    });
}

/// How colliders look when the editor shows them (Renderer.mShowColliders): a faint see-through fill, and a solid band
/// along a box's edges or round a sphere's outline. One look for every collider for now
const COLLIDER_FILL = Vec4(f32){ .x = 0.2, .y = 1.0, .z = 0.4, .w = 0.15 };
const COLLIDER_EDGE = Vec4(f32){ .x = 0.2, .y = 1.0, .z = 0.4, .w = 0.9 };
/// how wide the band is on screen, in pixels at the display's scale, however near or far the collider is
pub const COLLIDER_EDGE_PIXELS: f32 = 2.0;

/// The shadings every collider a render draws is painted with, added once for all of them
pub const ColliderShadings = struct {
    Fill: u32,
    Edge: u32,
};

/// Adds the colliders' fill and edge shadings: plain white tinted by each color
pub fn AddColliderShadings(engine_context: *EngineContext, shading_buff: *ShadingBuffers) !ColliderShadings {
    var plain = SurfaceComponent{};
    plain.mTexture.mManager = &engine_context.mAssetManager;
    const texture_asset = try plain.mTexture.GetAsset(engine_context, Texture2D);
    var fill: Texture2D.TexOptions = .default;
    fill.mColor = COLLIDER_FILL;
    var edge: Texture2D.TexOptions = .default;
    edge.mColor = COLLIDER_EDGE;
    return .{
        .Fill = @intCast(try shading_buff.AddSurface(engine_context.EngineAllocator(), &fill, texture_asset)),
        .Edge = @intCast(try shading_buff.AddSurface(engine_context.EngineAllocator(), &edge, texture_asset)),
    };
}

/// Draws a collider (ColliderShape), in the overlay pass for an overlay entity
pub fn DrawCollider(
    self: *Renderer2D,
    buffers: *RenderBuffers, //the pass it is drawn in
    engine_context: *EngineContext,
    transform_component: *const EntityTransformComponent,
    collider: *const ColliderComponent,
    canvas: ?CanvasTransform, //set for overlay scenes, whose transforms are in canvas units, and drawn in the overlay pass
    camera_view: CameraView,
    shadings: ColliderShadings,
) !void {
    _ = self;
    const drawn = ColliderShape(transform_component, collider, canvas, camera_view);
    try buffers.AddShape(engine_context.EngineAllocator(), drawn.Shape, .{
        .ShadingHandle = shadings.Fill,
        .BorderShadingHandle = shadings.Edge,
        .BorderWidth = drawn.EdgeWidth,
    });
}

/// A collider as it's drawn: its shape, and how wide its edge band is
pub const DrawnCollider = struct {
    Shape: ShapeData,
    EdgeWidth: f32,
};

/// A collider as the solid physics tests: its box (with the corners sharp, the way picking and raycasts test it) or its
/// sphere, see-through, with the band along its edges COLLIDER_EDGE_PIXELS wide on screen at its center's distance from
/// the camera. Never cut by a mask, the same as raycasts against colliders, and never picked, since picking tests the
/// entities' visuals. Its SurfaceIndex is AddShape's to fill in
pub fn ColliderShape(transform_component: *const EntityTransformComponent, collider: *const ColliderComponent, canvas: ?CanvasTransform, camera_view: CameraView) DrawnCollider {
    const Solid = struct { Center: Vec3(f32), Rotation: Quat(f32), Size: Vec3(f32), Type: ShapeType };
    const solid: Solid = switch (collider.mShape) {
        .Box => blk: {
            const box = ShapeGeometry.ColliderBox(transform_component, collider, canvas);
            break :blk .{ .Center = box.Center, .Rotation = box.Rotation, .Size = box.HalfExtents, .Type = .Box };
        },
        .Sphere => blk: {
            const sphere = ShapeGeometry.ColliderSphere(transform_component, collider, canvas);
            const radius = Vec3(f32){ .x = sphere.Radius, .y = sphere.Radius, .z = sphere.Radius };
            break :blk .{ .Center = sphere.Center, .Rotation = .{ .w = 1, .x = 0, .y = 0, .z = 0 }, .Size = radius, .Type = .Sphere };
        },
    };

    //one pixel's size in world units at the center's distance, from how much the view takes in from top to bottom
    const distance = solid.Center.SubVec(camera_view.Pose.Position).Len();
    const pixel_size = if (camera_view.TargetHeight > 0) 2.0 * distance * camera_view.TanHalfFov / camera_view.TargetHeight else 0;
    const axes = ShapeAxes(solid.Center, solid.Rotation);
    return .{
        .Shape = .{
            .AxisX = axes[0],
            .AxisY = axes[1],
            .AxisZ = axes[2],
            .Size = solid.Size.ToArray(),
            .Params = .{ 0, 0, 0, 0 },
            .Type = solid.Type,
            .MaskIndex = SDFProgram.NO_MASK,
            .SurfaceIndex = undefined,
            .Flags = ShapeData.FLAG_TRANSPARENT,
        },
        .EdgeWidth = COLLIDER_EDGE_PIXELS * camera_view.DisplayScale * pixel_size,
    };
}

/// A plain white surface's shading, for a merge's parts that nothing paints
fn PlainShading(engine_context: *EngineContext, shading_buff: *ShadingBuffers, plain: *SurfaceComponent) !usize {
    const texture_asset = try plain.mTexture.GetAsset(engine_context, Texture2D);
    return shading_buff.AddSurface(engine_context.EngineAllocator(), &plain.mTexOptions, texture_asset);
}

pub fn DrawText(
    self: *Renderer2D,
    buffers: *RenderBuffers, //the pass it is drawn in
    engine_context: *EngineContext,
    transform_component: *EntityTransformComponent,
    text_component: *TextComponent,
    surface: *SurfaceComponent, //what it is painted with
    canvas: ?CanvasTransform, //set for overlay scenes, whose transforms are in canvas units, and drawn in the overlay pass
    mask: u32, //the mask it is cut by, into `masks`, SDFProgram.NO_MASK for none
    masks: *const ShapeGeometry.ViewMasks,
    shading_buff: *ShadingBuffers,
) !void {
    const zone = Tracy.ZoneInit("Renderer2D::DrawText", @src());
    defer zone.Deinit();

    const fill = try TextFill.Of(engine_context, text_component, surface, shading_buff);
    //laid out in the text's own space, the same as picking measures it, then stretched by its scale on each axis
    const params = ShapeGeometry.GetTextParams(transform_component, text_component);
    var layout = TextLayout.Iterator(TextAsset).Init(text_component.mText.items, fill.Font, params.FontSize, params.WrapWidth);
    while (layout.Next()) |glyph| try self.DrawGlyph(buffers, engine_context, transform_component, params, glyph, fill, canvas, mask, masks, shading_buff);
}

/// What every letter of one text is painted with: its fill's shading (the text's color and texture), whether that is
/// see-through, and the font whose atlas its letters are cut from
pub const TextFill = struct {
    Shading: u32,
    Flags: u32,
    Font: *TextAsset,

    /// Adds the text's fill shading
    pub fn Of(engine_context: *EngineContext, text_component: *TextComponent, surface: *SurfaceComponent, shading_buff: *ShadingBuffers) !TextFill {
        const font = try text_component.mTextAssetHandle.GetAsset(engine_context, TextAsset);
        const texture_asset = try surface.mTexture.GetAsset(engine_context, Texture2D);
        const shading = try shading_buff.AddSurface(engine_context.EngineAllocator(), &surface.mTexOptions, texture_asset);
        return .{
            .Shading = @intCast(shading),
            .Flags = if (surface.mTexOptions.mIsTransparent) ShapeData.FLAG_TRANSPARENT else 0,
            .Font = font,
        };
    }
};

/// Draws one laid out letter of a text (TextLayout.GlyphPlacement), painted with its text's fill. Nothing is drawn for a
/// letter its mask cuts off altogether
pub fn DrawGlyph(
    self: *Renderer2D,
    buffers: *RenderBuffers, //the pass it is drawn in
    engine_context: *EngineContext,
    transform_component: *const EntityTransformComponent,
    params: ShapeGeometry.TextParams,
    glyph: TextLayout.GlyphPlacement,
    fill: TextFill,
    canvas: ?CanvasTransform, //set for overlay scenes, whose transforms are in canvas units, and drawn in the overlay pass
    mask: u32, //the mask it is cut by, into `masks`, SDFProgram.NO_MASK for none
    masks: *const ShapeGeometry.ViewMasks,
    shading_buff: *ShadingBuffers,
) !void {
    _ = self;
    //placed once here rather than for every pixel and step on the GPU
    const glyph_box = ShapeGeometry.GlyphBox(transform_component, params, glyph, canvas);
    //a letter cut off altogether isn't sent
    if (masks.CutsOff(mask, glyph_box)) return;

    //where the letter is in the font atlas, shared with every other glyph of the same letter this render
    const atlas_asset = &fill.Font.mAtlas;
    const atlas_shading_handle = try shading_buff.GlyphSurface(
        engine_context.EngineAllocator(),
        .{ .AtlasTexture = @intCast(atlas_asset.GetTextureHandle()), .Glyph = glyph.AtlasIndex },
        atlas_asset.GetWidth(),
        atlas_asset.GetHeight(),
        glyph.UV0,
        glyph.UV1,
    );

    const axes = ShapeAxes(glyph_box.Center, glyph_box.Rotation);
    try buffers.AddShape(engine_context.EngineAllocator(), .{
        .AxisX = axes[0],
        .AxisY = axes[1],
        .AxisZ = axes[2],
        .Size = glyph_box.HalfExtents.ToArray(),
        .Params = .{ 0, 0, 0, 0 },
        .Type = .Glyph,
        .MaskIndex = mask,
        .SurfaceIndex = undefined,
        .Flags = fill.Flags,
    }, .{
        .ShadingHandle = @intCast(fill.Shading),
        .BorderShadingHandle = @intCast(fill.Shading),
        .BorderWidth = 0,
        .AtlasHandle = @intCast(atlas_shading_handle),
    });
}
