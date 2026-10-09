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


const StorageBufferBinding = @import("RenderPlatform.zig").StorageBufferBinding;
const TextLayout = @import("TextLayout.zig");
const CanvasTransform = @import("../Math/OverlayCanvas.zig").CanvasTransform;
const ShapeGeometry = @import("ShapeGeometry.zig");
const ShapeSort = @import("ShapeSort.zig");
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
    const unit_axes = [3]Vec3(f32){ .{ .x = 1, .y = 0, .z = 0 }, .{ .x = 0, .y = 1, .z = 0 }, .{ .x = 0, .y = 0, .z = 1 } };
    var axes: [3]Vec4(f32).ArrayT = undefined;
    for (unit_axes, &axes) |unit_axis, *axis| {
        const world_axis = unit_axis.QuatRotate(rotation);
        axis.* = .{ world_axis.x, world_axis.y, world_axis.z, -world_axis.Dot(center) };
    }
    return axes;
}

/// What only the shape that was hit needs: which surfaces it is shaded with. The same slots for every kind of shape,
/// read the way its Type says
pub const ShapeSurface = extern struct {
    //what a hit on the shape is painted with: a quad's surface, a glyph's text fill (its color and texture)
    ShadingHandle: u32,
    //a quad's border band's solid color surface, drawn instead of ShadingHandle's within BorderWidth of its edge.
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

    /// Each shape's sort key, in the order the shapes were added (ShapeSort). The buffer is uploaded in their sorted
    /// order, which mSortedShapes holds once SortShapes has run
    mSortEntries: std.ArrayList(ShapeSort.SortEntry) = .empty,
    mSortedShapes: std.ArrayList(ShapeData) = .empty,
    /// How many of the sorted shapes are direct, which all come first. Set by SortShapes
    mDirectCount: u32 = 0,

    /// Each shape's world space bounding box (SDFFunctions.aabbIMShape), in the order the shapes were added, like
    /// mShapeBufferBase. CPU only: what the BVH is built from
    mShapeBounds: std.ArrayList(Aabb) = .empty,

    /// The BVH over the direct shapes, built by SortShapes: its items are the direct shapes in their sorted order, so a
    /// leaf's items are a run of mSortedShapes
    mBVHItems: std.ArrayList(BVH.Item) = .empty,
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

        self.mSortEntries.deinit(engine_context.EngineAllocator());
        self.mSortedShapes.deinit(engine_context.EngineAllocator());
        self.mShapeBounds.deinit(engine_context.EngineAllocator());
        self.mBVHItems.deinit(engine_context.EngineAllocator());
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
                self.mSortEntries.clearAndFree(engine_allocator);
                self.mSortedShapes.clearAndFree(engine_allocator);
                self.mShapeBounds.clearAndFree(engine_allocator);
                self.mBVHItems.clearAndFree(engine_allocator);
                self.mBVHNodes.clearAndFree(engine_allocator);
            },
            .ClearRetainingCapacity => {
                self.mShapeBufferBase.clearRetainingCapacity();
                self.mSurfaceBufferBase.clearRetainingCapacity();
                self.mMaskBufferBase.clearRetainingCapacity();
                self.mPrograms.Clear();
                self.mSortEntries.clearRetainingCapacity();
                self.mSortedShapes.clearRetainingCapacity();
                self.mShapeBounds.clearRetainingCapacity();
                self.mBVHItems.clearRetainingCapacity();
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

        try self.SortShapes(engine_context.EngineAllocator());
        const shape_byte_size = self.mSortedShapes.items.len * @sizeOf(ShapeData);
        _ = self.mShapeBuffer.SetData(engine_context, copy_pass, self.mSortedShapes.items.ptr, shape_byte_size, 0);

        const surface_byte_size = self.mSurfaceBufferBase.items.len * @sizeOf(ShapeSurface);
        _ = self.mSurfaceBuffer.SetData(engine_context, copy_pass, self.mSurfaceBufferBase.items.ptr, surface_byte_size, 0);

        //masks and their shapes' programs
        const mask_byte_size = self.mMaskBufferBase.items.len * @sizeOf(SDFProgram.MaskData);
        _ = self.mMaskBuffer.SetData(engine_context, copy_pass, self.mMaskBufferBase.items.ptr, mask_byte_size, 0);
        const instrs = self.mPrograms.mInstrs.items;
        _ = self.mInstrBuffer.SetData(engine_context, copy_pass, instrs.ptr, instrs.len * @sizeOf(SDFProgram.Instr), 0);
        const parts = self.mPrograms.mParts.items;
        _ = self.mPartBuffer.SetData(engine_context, copy_pass, parts.ptr, parts.len * @sizeOf(SDFProgram.Part), 0);

        //the BVH over the direct shapes, built by SortShapes
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

    /// The shapes in their keys' order, into mSortedShapes, ready to upload. Their surfaces and masks stay where they
    /// are, since a shape points at those rather than the other way round
    fn SortShapes(self: *RenderBuffers, engine_allocator: std.mem.Allocator) !void {
        const zone = Tracy.ZoneInit("Renderer2D::SortShapes", @src());
        defer zone.Deinit();
        zone.Value(self.mSortEntries.items.len);

        self.SetMortonOrders();
        ShapeSort.Sort(self.mSortEntries.items);
        try self.mSortedShapes.resize(engine_allocator, self.mShapeBufferBase.items.len);
        ShapeSort.Gather(ShapeData, self.mShapeBufferBase.items, self.mSortEntries.items, self.mSortedShapes.items);
        self.mDirectCount = ShapeSort.DirectCount(self.mSortEntries.items);
        try self.BuildBVH(engine_allocator);
    }

    /// The BVH over the direct shapes, which the sort has just put first and in Morton order: each one's code, box and
    /// mask, in that order
    fn BuildBVH(self: *RenderBuffers, engine_allocator: std.mem.Allocator) !void {
        const zone = Tracy.ZoneInit("Renderer2D::BuildBVH", @src());
        defer zone.Deinit();
        zone.Value(self.mDirectCount);

        try self.mBVHItems.resize(engine_allocator, self.mDirectCount);
        for (self.mSortEntries.items[0..self.mDirectCount], self.mBVHItems.items) |entry, *item| {
            item.* = .{ .Code = entry.Key.Order, .Bounds = self.mShapeBounds.items[entry.Index], .Mask = BVH.Mask.RENDER };
        }
        try BVH.Build(engine_allocator, self.mBVHItems.items, &self.mBVHNodes);
    }

    /// Each direct shape's key gets its Morton code (BVH.MortonCode) as its Order, from where its bounding box's center
    /// is among all the direct shapes' centers, so sorting puts shapes close in space next to each other: the order
    /// the BVH is built from. Marched shapes keep their Order, which is their place in their group
    fn SetMortonOrders(self: *RenderBuffers) void {
        var centers = Aabb.empty;
        for (self.mSortEntries.items) |entry| {
            if (entry.Key.Path != .Direct) continue;
            const center = self.mShapeBounds.items[entry.Index].Center();
            centers = centers.Union(.{ .Min = center, .Max = center });
        }
        for (self.mSortEntries.items) |*entry| {
            if (entry.Key.Path != .Direct) continue;
            entry.Key.Order = BVH.MortonCode(self.mShapeBounds.items[entry.Index].Center(), centers);
        }
    }

    /// Adds a shape and its surface, pointing the shape at it, and the key it is sorted by. The shape's SurfaceIndex
    /// is filled in here
    fn AddShape(self: *RenderBuffers, engine_allocator: std.mem.Allocator, shape: ShapeData, surface: ShapeSurface, key: ShapeSort.ShapeSortKey) !void {
        var added = shape;
        added.SurfaceIndex = @intCast(self.mSurfaceBufferBase.items.len);
        try self.mSortEntries.append(engine_allocator, .{ .Key = key, .Index = @intCast(self.mShapeBufferBase.items.len) });
        try self.mSurfaceBufferBase.append(engine_allocator, surface);
        try self.mShapeBufferBase.append(engine_allocator, added);
        try self.mShapeBounds.append(engine_allocator, SDFFunctions.aabbIMShape(added));
        switch (shape.Type) {
            .Quad => self.mQuadCount += 1,
            .Glyph => self.mGlyphCount += 1,
            .Merge => self.mMergeCount += 1,
            .None => {},
        }
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

/// The view's masks (ShapeGeometry.ViewMasks), which every shape drawn this batch points into by its MaskIndex. Both
/// passes get all of them: a mask only ever cuts shapes in its own layer, and there are few
pub fn SetMasks(self: *Renderer2D, engine_allocator: std.mem.Allocator, masks: *const ShapeGeometry.ViewMasks) !void {
    for ([_]*RenderBuffers{ &self.mGameData, &self.mOverlayData }) |buffers| {
        //first, while they are empty, so the masks' program ranges stay right
        std.debug.assert(buffers.mPrograms.mInstrs.items.len == 0);
        try buffers.mMaskBufferBase.appendSlice(engine_allocator, masks.mMasks.items);
        try buffers.mPrograms.mInstrs.appendSlice(engine_allocator, masks.mPrograms.mInstrs.items);
        try buffers.mPrograms.mParts.appendSlice(engine_allocator, masks.mPrograms.mParts.items);
        try buffers.mPrograms.mPartSurfaces.appendSlice(engine_allocator, masks.mPrograms.mPartSurfaces.items);
    }
}

pub fn SetBuffers(self: *Renderer2D, stats: *RenderStats, engine_context: *EngineContext, copy_pass: *anyopaque, pipeline_t: PipelineType) !void {
    try switch (pipeline_t) {
        .GamePipeline => self.mGameData.SetBuffers(stats, engine_context, copy_pass),
        .OverlayPipeline => self.mOverlayData.SetBuffers(stats, engine_context, copy_pass),
    };
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

pub fn DrawQuad(
    self: *Renderer2D,
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
            std.math.maxInt(u32),
        );

    var shading_flag: u32 = 0;
    if (surface.mTexOptions.mIsTransparent) shading_flag |= ShapeData.FLAG_TRANSPARENT;

    //the border is a solid color: its own surface, which the marcher draws untextured
    var border_shading_handle = shading_handle;
    if (box.BorderWidth > 0) {
        var border_options: Texture2D.TexOptions = .default;
        border_options.mColor = surface.mBorderColor;
        border_shading_handle = try shading_buff.AddSurface(engine_context.EngineAllocator(), &border_options, texture_asset, std.math.maxInt(u32));
        if (surface.mBorderColor.w < 1.0) shading_flag |= ShapeData.FLAG_TRANSPARENT;
    }

    const buffers = if (canvas != null) &self.mOverlayData else &self.mGameData;

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
    }, .{});
}

/// Draws a merge (MergeComponent) as one shape: compiled into its pass's programs, a plate over the rectangle its parts
/// lie within, where its program says, each part painted with its surface the way a quad is, blended where they meet.
/// Its root's surface, if it has one, gives its border, around the whole merged outline
pub fn DrawMerge(
    self: *Renderer2D,
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

    const buffers = if (canvas != null) &self.mOverlayData else &self.mGameData;
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
    const shading_handle = try shading_buff.AddSurface(engine_allocator, &surface.mTexOptions, texture_asset, std.math.maxInt(u32));

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
            known.value_ptr.* = @intCast(try shading_buff.AddSurface(engine_allocator, &painter_surface.mTexOptions, painter_texture, std.math.maxInt(u32)));
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
        border_shading_handle = try shading_buff.AddSurface(engine_allocator, &border_options, texture_asset, std.math.maxInt(u32));
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
    }, .{});
}

/// A plain white surface's shading, for a merge's parts that nothing paints
fn PlainShading(engine_context: *EngineContext, shading_buff: *ShadingBuffers, plain: *SurfaceComponent) !usize {
    const texture_asset = try plain.mTexture.GetAsset(engine_context, Texture2D);
    return shading_buff.AddSurface(engine_context.EngineAllocator(), &plain.mTexOptions, texture_asset, std.math.maxInt(u32));
}

pub fn DrawText(
    self: *Renderer2D,
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

    const text_asset = try text_component.mTextAssetHandle.GetAsset(engine_context, TextAsset);
    const atlas_asset = &text_asset.mAtlas;
    const texture_asset = try surface.mTexture.GetAsset(engine_context, Texture2D);

    const texture_shading_handle = try shading_buff.AddSurface(
        engine_context.EngineAllocator(),
        &surface.mTexOptions,
        texture_asset,
        std.math.maxInt(u32),
    );

    var texture_shading_flags: u32 = 0;
    if (surface.mTexOptions.mIsTransparent) texture_shading_flags |= ShapeData.FLAG_TRANSPARENT;

    //the text's own position and rotation, in canvas units for an overlay scene
    const text_pos = transform_component.GetWorldPosition();
    const text_rot = transform_component.GetWorldRotation();

    //every glyph turns with the text, and with the canvas on top of that
    const glyph_rot = if (canvas) |c| c.ToWorldRotation(text_rot) else text_rot;
    const size_scale: f32 = if (canvas) |c| c.Scale else 1.0;

    const buffers = if (canvas != null) &self.mOverlayData else &self.mGameData;

    //font size and bounds with the text's scale applied, the same ones picking measures the text with
    const params = ShapeGeometry.GetTextParams(transform_component, text_component);

    var layout = TextLayout.Iterator(TextAsset).Init(text_component.mText.items, text_asset, params.FontSize, params.WrapWidth);
    while (layout.Next()) |glyph| {
        //the layout is in the text's own space, so the whole line turns with the transform instead
        //of each glyph turning in place along world x
        const local_pen = Vec3(f32){ .x = glyph.Pen.x - params.LeftBound, .y = glyph.Pen.y, .z = 0 };
        var pen_pos = text_pos.AddVec(local_pen.QuatRotate(text_rot));
        if (canvas) |c| pen_pos = c.ToWorldPoint(pen_pos);
        const half_extents = Vec3(f32){ .x = glyph.HalfExtents.x * size_scale, .y = glyph.HalfExtents.y * size_scale, .z = THICKNESS_2D };

        //the box sits PlaneCenter off the pen in the glyph's own plane. Worked out once here rather than for
        //every pixel and step on the GPU
        const plane_offset = (Vec3(f32){ .x = glyph.PlaneCenter.x * size_scale, .y = glyph.PlaneCenter.y * size_scale, .z = 0 }).QuatRotate(glyph_rot);
        const glyph_center = pen_pos.AddVec(plane_offset);

        //a letter cut off altogether isn't sent
        const glyph_box = ShapeGeometry.Box{ .Center = glyph_center, .Rotation = glyph_rot, .HalfExtents = half_extents };
        if (masks.CutsOff(mask, glyph_box)) continue;

        var tex_options = Texture2D.TexOptions{
            .mColor = Vec4(f32){ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 },
            .mIsTransparent = false,
            .mTextureUV0 = glyph.UV0,
            .mTextureUV1 = glyph.UV1,
            .mTilingFactor = 1.0,
        };

        const atlas_shading_handle = try shading_buff.AddSurface(
            engine_context.EngineAllocator(),
            &tex_options,
            atlas_asset,
            texture_shading_handle,
        );

        const axes = ShapeAxes(glyph_center, glyph_rot);
        try buffers.AddShape(engine_context.EngineAllocator(), .{
            .AxisX = axes[0],
            .AxisY = axes[1],
            .AxisZ = axes[2],
            .Size = half_extents.ToArray(),
            .Params = .{ 0, 0, 0, 0 },
            .Type = .Glyph,
            .MaskIndex = mask,
            .SurfaceIndex = undefined,
            .Flags = texture_shading_flags,
        }, .{
            .ShadingHandle = @intCast(atlas_shading_handle),
            .BorderShadingHandle = @intCast(atlas_shading_handle),
            .BorderWidth = 0,
        }, .{});
    }
}
