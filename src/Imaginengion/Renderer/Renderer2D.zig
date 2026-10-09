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
    //which ClipData it is cut to, NO_CLIP for none
    ClipIndex: u32,
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
    //a quad's surface, a glyph's atlas entry
    ShadingHandle: u32,
    //a quad's border band's solid color surface, drawn instead of ShadingHandle's within BorderWidth of its edge.
    //ShadingHandle again for a shape without a border
    BorderShadingHandle: u32,
    //a quad's border: world units, already scaled and kept to at most half the smaller side. 0 for none
    BorderWidth: f32,
    _Pad: u32 = 0,
};

/// A clip region's rectangle (ClipComponent), in world space: a shape with its index is only drawn where it is inside
/// it, measured in the rectangle's own plane, so the cut goes straight through depth. Shared by every shape under the
/// region, which is why it is a buffer of its own rather than a copy in each shape
pub const ClipData = extern struct {
    Rotation: if (is_spirv) Vec4(f32).VectorT else Vec4(f32).ArrayT,
    Position: if (is_spirv) Vec3(f32).VectorT else Vec3(f32).ArrayT,
    HalfExtents: if (is_spirv) Vec2(f32).VectorT else Vec2(f32).ArrayT align(16),
};

/// A shape's ClipIndex when it isn't inside any clip region
pub const NO_CLIP: u32 = std.math.maxInt(u32);

comptime {
    GPUAsserts.AssertGPULayout(ShapeData);
    GPUAsserts.AssertGPULayout(ShapeSurface);
    GPUAsserts.AssertGPULayout(ClipData);
}

pub const RenderBuffers = struct {
    mShapeBuffer: SSBO = .{},
    mShapeBufferBase: std.ArrayList(ShapeData) = .empty,

    mSurfaceBuffer: SSBO = .{},
    mSurfaceBufferBase: std.ArrayList(ShapeSurface) = .empty,

    mClipBuffer: SSBO = .{},
    mClipBufferBase: std.ArrayList(ClipData) = .empty,
    /// Each clip region's index in mClipBufferBase this batch, so its shapes share one entry
    mClipIndices: std.AutoHashMapUnmanaged(Entity.Type, u32) = .empty,

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

    pub fn Init(self: *RenderBuffers, engine_context: *EngineContext) !void {
        self.mShapeBuffer.Init(engine_context, @sizeOf(ShapeData) * 100, 2, .Compute);
        self.mShapeBufferBase = try std.ArrayList(ShapeData).initCapacity(engine_context.EngineAllocator(), 100);

        self.mSurfaceBuffer.Init(engine_context, @sizeOf(ShapeSurface) * 100, 3, .Compute);
        self.mSurfaceBufferBase = try std.ArrayList(ShapeSurface).initCapacity(engine_context.EngineAllocator(), 100);

        self.mClipBuffer.Init(engine_context, @sizeOf(ClipData) * 16, 4, .Compute);
        self.mClipBufferBase = try std.ArrayList(ClipData).initCapacity(engine_context.EngineAllocator(), 16);

        //a tree over 100 shapes in leaves of up to 4 is around 50 to 70 nodes
        self.mNodeBuffer.Init(engine_context, @sizeOf(BVH.Node) * 64, 5, .Compute);
    }
    pub fn Deinit(self: *RenderBuffers, engine_context: *EngineContext) void {
        self.mShapeBuffer.Deinit(engine_context);
        self.mShapeBufferBase.deinit(engine_context.EngineAllocator());

        self.mSurfaceBuffer.Deinit(engine_context);
        self.mSurfaceBufferBase.deinit(engine_context.EngineAllocator());

        self.mClipBuffer.Deinit(engine_context);
        self.mClipBufferBase.deinit(engine_context.EngineAllocator());
        self.mClipIndices.deinit(engine_context.EngineAllocator());

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
                self.mClipBufferBase.clearAndFree(engine_allocator);
                self.mClipIndices.clearAndFree(engine_allocator);
                self.mSortEntries.clearAndFree(engine_allocator);
                self.mSortedShapes.clearAndFree(engine_allocator);
                self.mShapeBounds.clearAndFree(engine_allocator);
                self.mBVHItems.clearAndFree(engine_allocator);
                self.mBVHNodes.clearAndFree(engine_allocator);
            },
            .ClearRetainingCapacity => {
                self.mShapeBufferBase.clearRetainingCapacity();
                self.mSurfaceBufferBase.clearRetainingCapacity();
                self.mClipBufferBase.clearRetainingCapacity();
                self.mClipIndices.clearRetainingCapacity();
                self.mSortEntries.clearRetainingCapacity();
                self.mSortedShapes.clearRetainingCapacity();
                self.mShapeBounds.clearRetainingCapacity();
                self.mBVHItems.clearRetainingCapacity();
                self.mBVHNodes.clearRetainingCapacity();
            },
        }
        self.mQuadCount = 0;
        self.mGlyphCount = 0;
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

        //clip regions
        const clip_byte_size = self.mClipBufferBase.items.len * @sizeOf(ClipData);
        _ = self.mClipBuffer.SetData(engine_context, copy_pass, self.mClipBufferBase.items.ptr, clip_byte_size, 0);

        //the BVH over the direct shapes, built by SortShapes
        const node_byte_size = self.mBVHNodes.items.len * @sizeOf(BVH.Node);
        _ = self.mNodeBuffer.SetData(engine_context, copy_pass, self.mBVHNodes.items.ptr, node_byte_size, 0);
        //added to stats: the overlay and game passes each have their own quads and glyphs
        stats.OutputQuadNum += self.mQuadCount;
        stats.OutputGlyphNum += self.mGlyphCount;
    }
    pub fn BindBuffers(self: RenderBuffers, render_pass: *anyopaque) void {
        self.mShapeBuffer.Bind(render_pass);
        self.mSurfaceBuffer.Bind(render_pass);
        self.mClipBuffer.Bind(render_pass);
        self.mNodeBuffer.Bind(render_pass);
    }

    /// The shapes in their keys' order, into mSortedShapes, ready to upload. Their surfaces and clips stay where they
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
            .None => {},
        }
    }

    /// The index of a shape's clip region in this batch's clips, adding it the first time one of its shapes asks.
    /// NO_CLIP for a shape not in one
    fn ClipIndex(self: *RenderBuffers, engine_allocator: std.mem.Allocator, clip: ?ShapeGeometry.ViewClip) !u32 {
        const view_clip = clip orelse return NO_CLIP;
        const entry = try self.mClipIndices.getOrPut(engine_allocator, view_clip.Owner);
        if (!entry.found_existing) {
            entry.value_ptr.* = @intCast(self.mClipBufferBase.items.len);
            try self.mClipBufferBase.append(engine_allocator, .{
                .Rotation = view_clip.Rect.Rotation.ToArray(),
                .Position = view_clip.Rect.Center.ToArray(),
                .HalfExtents = view_clip.Rect.HalfExtents.ToArray(),
            });
        }
        return entry.value_ptr.*;
    }
};

mGameData: RenderBuffers = .{},
mOverlayData: RenderBuffers = .{},

pub fn Init(self: *Renderer2D, engine_context: *EngineContext) !void {
    try self.mGameData.Init(engine_context);
    try self.mOverlayData.Init(engine_context);
}

pub fn Deinit(self: *Renderer2D, engine_context: *EngineContext) void {
    self.mGameData.Deinit(engine_context);
    self.mOverlayData.Deinit(engine_context);
}

pub fn StartBatch(self: *Renderer2D, engine_allocator: std.mem.Allocator) void {
    self.mGameData.Reset(engine_allocator, .ClearRetainingCapacity);
    self.mOverlayData.Reset(engine_allocator, .ClearRetainingCapacity);
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
    clip: ?ShapeGeometry.ViewClip, //the clip region it is inside, if any
    shading_buff: *ShadingBuffers,
) !void {
    //the same box picking tests against
    const box = ShapeGeometry.QuadBox(transform_component, quad, surface.mBorderWidth, canvas);
    //cut off altogether: nothing to draw, and nothing for every pixel to march past
    if (clip) |view_clip| {
        if (ShapeGeometry.OutsideClip(box, view_clip.Rect)) return;
    }

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
    const clip_index = try buffers.ClipIndex(engine_context.EngineAllocator(), clip);

    const axes = ShapeAxes(box.Center, box.Rotation);
    try buffers.AddShape(engine_context.EngineAllocator(), .{
        .AxisX = axes[0],
        .AxisY = axes[1],
        .AxisZ = axes[2],
        .Size = box.HalfExtents.ToArray(),
        .Params = box.CornerRadii.ToArray(),
        .Type = .Quad,
        .ClipIndex = clip_index,
        .SurfaceIndex = undefined,
        .Flags = shading_flag,
    }, .{
        .ShadingHandle = @intCast(shading_handle),
        .BorderShadingHandle = @intCast(border_shading_handle),
        .BorderWidth = box.BorderWidth,
    }, .{});
}

pub fn DrawText(
    self: *Renderer2D,
    engine_context: *EngineContext,
    transform_component: *EntityTransformComponent,
    text_component: *TextComponent,
    surface: *SurfaceComponent, //what it is painted with
    canvas: ?CanvasTransform, //set for overlay scenes, whose transforms are in canvas units, and drawn in the overlay pass
    clip: ?ShapeGeometry.ViewClip, //the clip region it is inside, if any
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
    const clip_index = try buffers.ClipIndex(engine_context.EngineAllocator(), clip);

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
        if (clip) |view_clip| {
            const glyph_box = ShapeGeometry.Box{ .Center = glyph_center, .Rotation = glyph_rot, .HalfExtents = half_extents };
            if (ShapeGeometry.OutsideClip(glyph_box, view_clip.Rect)) continue;
        }

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
            .ClipIndex = clip_index,
            .SurfaceIndex = undefined,
            .Flags = texture_shading_flags,
        }, .{
            .ShadingHandle = @intCast(atlas_shading_handle),
            .BorderShadingHandle = @intCast(atlas_shading_handle),
            .BorderWidth = 0,
        }, .{});
    }
}
