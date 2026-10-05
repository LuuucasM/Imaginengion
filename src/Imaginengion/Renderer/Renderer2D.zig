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

const THICKNESS_2D = @import("../Math/SDFFunctions.zig").THICKNESS_2D;

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const EntityTransformComponent = EntityComponents.TransformComponent;
const QuadComponent = EntityComponents.QuadComponent;
const TextComponent = EntityComponents.TextComponent;


const StorageBufferBinding = @import("RenderPlatform.zig").StorageBufferBinding;
const TextLayout = @import("TextLayout.zig");
const CanvasTransform = @import("../Math/OverlayCanvas.zig").CanvasTransform;
const ShapeGeometry = @import("ShapeGeometry.zig");
const ShapeSort = @import("ShapeSort.zig");
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

    Rotation: if (is_spirv) Vec4(f32).VectorT else Vec4(f32).ArrayT,
    //the center of the shape. For a glyph that is its box's center, not the pen position it was laid out from
    Position: if (is_spirv) Vec3(f32).VectorT else Vec3(f32).ArrayT,
    //half extents for the box shapes, quads and glyphs, including their THICKNESS_2D depth
    Size: if (is_spirv) Vec3(f32).VectorT else Vec3(f32).ArrayT align(16),
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
            },
            .ClearRetainingCapacity => {
                self.mShapeBufferBase.clearRetainingCapacity();
                self.mSurfaceBufferBase.clearRetainingCapacity();
                self.mClipBufferBase.clearRetainingCapacity();
                self.mClipIndices.clearRetainingCapacity();
                self.mSortEntries.clearRetainingCapacity();
                self.mSortedShapes.clearRetainingCapacity();
            },
        }
        self.mQuadCount = 0;
        self.mGlyphCount = 0;
    }
    pub fn SetBuffers(self: *RenderBuffers, stats: *RenderStats, engine_context: *EngineContext) !void {
        const zone = Tracy.ZoneInit("Renderer2D::SetBuffers", @src());
        defer zone.Deinit();

        try self.SortShapes(engine_context.EngineAllocator());
        const shape_byte_size = self.mSortedShapes.items.len * @sizeOf(ShapeData);
        _ = self.mShapeBuffer.SetData(engine_context, self.mSortedShapes.items.ptr, shape_byte_size, 0);

        const surface_byte_size = self.mSurfaceBufferBase.items.len * @sizeOf(ShapeSurface);
        _ = self.mSurfaceBuffer.SetData(engine_context, self.mSurfaceBufferBase.items.ptr, surface_byte_size, 0);

        //clip regions
        const clip_byte_size = self.mClipBufferBase.items.len * @sizeOf(ClipData);
        _ = self.mClipBuffer.SetData(engine_context, self.mClipBufferBase.items.ptr, clip_byte_size, 0);
        //added to stats: the overlay and game passes each have their own quads and glyphs
        stats.OutputQuadNum += self.mQuadCount;
        stats.OutputGlyphNum += self.mGlyphCount;
    }
    pub fn BindBuffers(self: RenderBuffers, render_pass: *anyopaque) void {
        self.mShapeBuffer.Bind(render_pass);
        self.mSurfaceBuffer.Bind(render_pass);
        self.mClipBuffer.Bind(render_pass);
    }

    /// The shapes in their keys' order, into mSortedShapes, ready to upload. Their surfaces and clips stay where they
    /// are, since a shape points at those rather than the other way round
    fn SortShapes(self: *RenderBuffers, engine_allocator: std.mem.Allocator) !void {
        const zone = Tracy.ZoneInit("Renderer2D::SortShapes", @src());
        defer zone.Deinit();
        zone.Value(self.mSortEntries.items.len);

        ShapeSort.Sort(self.mSortEntries.items);
        try self.mSortedShapes.resize(engine_allocator, self.mShapeBufferBase.items.len);
        ShapeSort.Gather(ShapeData, self.mShapeBufferBase.items, self.mSortEntries.items, self.mSortedShapes.items);
    }

    /// Adds a shape and its surface, pointing the shape at it, and the key it is sorted by. The shape's SurfaceIndex
    /// is filled in here
    fn AddShape(self: *RenderBuffers, engine_allocator: std.mem.Allocator, shape: ShapeData, surface: ShapeSurface, key: ShapeSort.ShapeSortKey) !void {
        var added = shape;
        added.SurfaceIndex = @intCast(self.mSurfaceBufferBase.items.len);
        try self.mSortEntries.append(engine_allocator, .{ .Key = key, .Index = @intCast(self.mShapeBufferBase.items.len) });
        try self.mSurfaceBufferBase.append(engine_allocator, surface);
        try self.mShapeBufferBase.append(engine_allocator, added);
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

pub fn SetBuffers(self: *Renderer2D, stats: *RenderStats, engine_context: *EngineContext, pipeline_t: PipelineType) !void {
    try switch (pipeline_t) {
        .GamePipeline => self.mGameData.SetBuffers(stats, engine_context),
        .OverlayPipeline => self.mOverlayData.SetBuffers(stats, engine_context),
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

pub fn DrawQuad(
    self: *Renderer2D,
    engine_context: *EngineContext,
    transform_component: *EntityTransformComponent,
    quad_component: *QuadComponent,
    shown: ?RenderTargetComponent.Shown, //a render target it shows in place of its texture (ViewportComponent)
    canvas: ?CanvasTransform, //set for overlay scenes, whose transforms are in canvas units, and drawn in the overlay pass
    clip: ?ShapeGeometry.ViewClip, //the clip region it is inside, if any
    shading_buff: *ShadingBuffers,
) !void {
    //the same box picking tests against
    const box = ShapeGeometry.QuadBox(transform_component, quad_component, canvas);
    //cut off altogether: nothing to draw, and nothing for every pixel to march past
    if (clip) |view_clip| {
        if (ShapeGeometry.OutsideClip(box, view_clip.Rect)) return;
    }

    const texture_asset = try quad_component.mTexture.GetAsset(engine_context, Texture2D);

    const shading_handle = if (shown) |target|
        try shading_buff.AddSurfaceSlot(engine_context.EngineAllocator(), &quad_component.mTexOptions, target.Handle, target.Width, target.Height)
    else
        try shading_buff.AddSurface(
            engine_context.EngineAllocator(),
            &quad_component.mTexOptions,
            texture_asset,
            std.math.maxInt(u32),
        );

    var shading_flag: u32 = 0;
    if (quad_component.mTexOptions.mIsTransparent) shading_flag |= ShapeData.FLAG_TRANSPARENT;

    //the border is a solid color: its own surface, which the marcher draws untextured
    var border_shading_handle = shading_handle;
    if (box.BorderWidth > 0) {
        var border_options: Texture2D.TexOptions = .default;
        border_options.mColor = quad_component.mBorderColor;
        border_shading_handle = try shading_buff.AddSurface(engine_context.EngineAllocator(), &border_options, texture_asset, std.math.maxInt(u32));
        if (quad_component.mBorderColor.w < 1.0) shading_flag |= ShapeData.FLAG_TRANSPARENT;
    }

    const buffers = if (canvas != null) &self.mOverlayData else &self.mGameData;
    const clip_index = try buffers.ClipIndex(engine_context.EngineAllocator(), clip);

    try buffers.AddShape(engine_context.EngineAllocator(), .{
        .Rotation = box.Rotation.ToArray(),
        .Position = box.Center.ToArray(),
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
    canvas: ?CanvasTransform, //set for overlay scenes, whose transforms are in canvas units, and drawn in the overlay pass
    clip: ?ShapeGeometry.ViewClip, //the clip region it is inside, if any
    shading_buff: *ShadingBuffers,
) !void {
    const zone = Tracy.ZoneInit("Renderer2D::DrawText", @src());
    defer zone.Deinit();

    const text_asset = try text_component.mTextAssetHandle.GetAsset(engine_context, TextAsset);
    const atlas_asset = &text_asset.mAtlas;
    const texture_asset = try text_component.mTexHandle.GetAsset(engine_context, Texture2D);

    const texture_shading_handle = try shading_buff.AddSurface(
        engine_context.EngineAllocator(),
        &text_component.mTexOptions,
        texture_asset,
        std.math.maxInt(u32),
    );

    var texture_shading_flags: u32 = 0;
    if (text_component.mTexOptions.mIsTransparent) texture_shading_flags |= ShapeData.FLAG_TRANSPARENT;

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

        try buffers.AddShape(engine_context.EngineAllocator(), .{
            .Rotation = glyph_rot.ToArray(),
            .Position = glyph_center.ToArray(),
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
