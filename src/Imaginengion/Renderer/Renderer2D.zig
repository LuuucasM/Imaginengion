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
const SurfShadingData = @import("Renderer.zig").SurfShadingData;
const MedShadingData = @import("Renderer.zig").MedShadingData;
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
const Entity = @import("../ECSObjects/Entity.zig");

const Tracy = @import("../Core/Tracy.zig");

const Renderer2D = @This();

const MAX_PATH_LEN = 256;

const is_spirv = builtin.target.cpu.arch.isSpirV();

const ResetOptions = enum {
    ClearAndFree,
    ClearRetainingCapacity,
};

pub const QuadData = extern struct {
    Rotation: if (is_spirv) Vec4(f32).VectorT else Vec4(f32).ArrayT,
    Position: if (is_spirv) Vec3(f32).VectorT else Vec3(f32).ArrayT,
    HalfExtents: if (is_spirv) Vec3(f32).VectorT else Vec3(f32).ArrayT align(16),
    //the shader's vec3 takes 16 bytes, so on the GPU this starts at 48, not right after the 12 bytes of [3]f32
    ShadingHandle: u32 align(16),
    ShadingFlags: u32,
    //the surface drawn in the border band instead of ShadingHandle's, when BorderWidth isn't 0
    BorderShadingHandle: u32,
    //world units, already scaled and kept to at most half the smaller side
    BorderWidth: f32,
    //world units, already scaled and clamped like BorderWidth, in SDFFunctions' order (x top right, y bottom
    //right, z top left, w bottom left)
    CornerRadii: if (is_spirv) Vec4(f32).VectorT else Vec4(f32).ArrayT align(16),
    //which ClipData it is cut to, NO_CLIP for none
    ClipIndex: u32,
};

pub const GlyphData = extern struct {
    Rotation: if (is_spirv) Vec4(f32).VectorT else Vec4(f32).ArrayT,
    Position: if (is_spirv) Vec3(f32).VectorT else Vec3(f32).ArrayT,
    HalfExtents: if (is_spirv) Vec3(f32).VectorT else Vec3(f32).ArrayT align(16),
    PlaneCenter: if (is_spirv) Vec2(f32).VectorT else Vec2(f32).ArrayT align(16),
    AtlasShadingHandle: u32,
    TextureShadingFlags: u32,
    //which ClipData it is cut to, NO_CLIP for none
    ClipIndex: u32,
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
    GPUAsserts.AssertGPULayout(QuadData);
    GPUAsserts.AssertGPULayout(GlyphData);
    GPUAsserts.AssertGPULayout(ClipData);
}

pub const BufferKind = enum {
    Quad,
    Glyph,
    Shading,
};

pub const RenderBuffers = struct {
    mQuadBuffer: SSBO = .{},
    mQuadBufferBase: std.ArrayList(QuadData) = .empty,

    mGlyphBuffer: SSBO = .{},
    mGlyphBufferBase: std.ArrayList(GlyphData) = .empty,

    mClipBuffer: SSBO = .{},
    mClipBufferBase: std.ArrayList(ClipData) = .empty,
    /// Each clip region's index in mClipBufferBase this batch, so its shapes share one entry
    mClipIndices: std.AutoHashMapUnmanaged(Entity.Type, u32) = .empty,

    pub fn Init(self: *RenderBuffers, engine_context: *EngineContext) !void {
        self.mQuadBuffer.Init(engine_context, @sizeOf(QuadData) * 100, 2, .Compute);
        self.mQuadBufferBase = try std.ArrayList(QuadData).initCapacity(engine_context.EngineAllocator(), 100);

        self.mGlyphBuffer.Init(engine_context, @sizeOf(GlyphData) * 100, 3, .Compute);
        self.mGlyphBufferBase = try std.ArrayList(GlyphData).initCapacity(engine_context.EngineAllocator(), 100);

        self.mClipBuffer.Init(engine_context, @sizeOf(ClipData) * 16, 4, .Compute);
        self.mClipBufferBase = try std.ArrayList(ClipData).initCapacity(engine_context.EngineAllocator(), 16);
    }
    pub fn Deinit(self: *RenderBuffers, engine_context: *EngineContext) void {
        self.mQuadBuffer.Deinit(engine_context);
        self.mQuadBufferBase.deinit(engine_context.EngineAllocator());

        self.mGlyphBuffer.Deinit(engine_context);
        self.mGlyphBufferBase.deinit(engine_context.EngineAllocator());

        self.mClipBuffer.Deinit(engine_context);
        self.mClipBufferBase.deinit(engine_context.EngineAllocator());
        self.mClipIndices.deinit(engine_context.EngineAllocator());
    }
    pub fn Reset(self: *RenderBuffers, engine_allocator: std.mem.Allocator, reset_options: ResetOptions) void {
        switch (reset_options) {
            .ClearAndFree => {
                self.mQuadBufferBase.clearAndFree(engine_allocator);
                self.mGlyphBufferBase.clearAndFree(engine_allocator);
                self.mClipBufferBase.clearAndFree(engine_allocator);
                self.mClipIndices.clearAndFree(engine_allocator);
            },
            .ClearRetainingCapacity => {
                self.mQuadBufferBase.clearRetainingCapacity();
                self.mGlyphBufferBase.clearRetainingCapacity();
                self.mClipBufferBase.clearRetainingCapacity();
                self.mClipIndices.clearRetainingCapacity();
            },
        }
    }
    pub fn SetBuffers(self: *RenderBuffers, stats: *RenderStats, engine_context: *EngineContext) !void {
        const zone = Tracy.ZoneInit("Renderer2D::SetBuffers", @src());
        defer zone.Deinit();

        const quad_byte_size = self.mQuadBufferBase.items.len * @sizeOf(QuadData);
        const glyph_byte_size = self.mGlyphBufferBase.items.len * @sizeOf(GlyphData);

        //quads
        _ = self.mQuadBuffer.SetData(engine_context, self.mQuadBufferBase.items.ptr, quad_byte_size, 0);

        //glyphs
        _ = self.mGlyphBuffer.SetData(engine_context, self.mGlyphBufferBase.items.ptr, glyph_byte_size, 0);

        //clip regions
        const clip_byte_size = self.mClipBufferBase.items.len * @sizeOf(ClipData);
        _ = self.mClipBuffer.SetData(engine_context, self.mClipBufferBase.items.ptr, clip_byte_size, 0);
        //fill out stats
        stats.OutputQuadNum = @intCast(self.mQuadBufferBase.items.len);
        stats.OutputGlyphNum = @intCast(self.mGlyphBufferBase.items.len);
    }
    pub fn BindBuffers(self: RenderBuffers, render_pass: *anyopaque) void {
        self.mQuadBuffer.Bind(render_pass);
        self.mGlyphBuffer.Bind(render_pass);
        self.mClipBuffer.Bind(render_pass);
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

pub fn GetBufferCount(self: Renderer2D, comptime buff_kind: BufferKind, pipeline_kind: PipelineType) u32 {
    return switch (pipeline_kind) {
        .GamePipeline => switch (buff_kind) {
            .Quad => @intCast(self.mGameData.mQuadBufferBase.items.len),
            .Glyph => @intCast(self.mGameData.mGlyphBufferBase.items.len),
            .Shading => @intCast(self.mGameData.mShadingBufferBase.items.len),
        },
        .OverlayPipeline => switch (buff_kind) {
            .Quad => @intCast(self.mOverlayData.mQuadBufferBase.items.len),
            .Glyph => @intCast(self.mOverlayData.mGlyphBufferBase.items.len),
            .Shading => @intCast(self.mOverlayData.mShadingBufferBase.items.len),
        },
    };
}

pub fn GetBuffer(self: Renderer2D, comptime buff_kind: BufferKind, pipeline_kind: PipelineType) *anyopaque {
    return switch (pipeline_kind) {
        .GamePipeline => switch (buff_kind) {
            .Quad => @intCast(self.mGameData.mQuadBuffer.GetBuffer()),
            .Glyph => @intCast(self.mGameData.mGlyphBuffer.GetBuffer()),
            .Shading => @intCast(self.mGameData.mShadingBuffer.GetBuffer()),
        },
        .OverlayPipeline => switch (buff_kind) {
            .Quad => @intCast(self.mOverlayData.mQuadBuffer.GetBuffer()),
            .Glyph => @intCast(self.mOverlayData.mGlyphBuffer.GetBuffer()),
            .Shading => @intCast(self.mOverlayData.mShadingBuffer.GetBuffer()),
        },
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
    if (quad_component.mTexOptions.mIsTransparent) shading_flag |= SurfShadingData.FLAG_TRANSPARENT;

    //the border is a solid color: its own surface, which the marcher draws untextured
    var border_shading_handle = shading_handle;
    if (box.BorderWidth > 0) {
        var border_options: Texture2D.TexOptions = .default;
        border_options.mColor = quad_component.mBorderColor;
        border_shading_handle = try shading_buff.AddSurface(engine_context.EngineAllocator(), &border_options, texture_asset, std.math.maxInt(u32));
        if (quad_component.mBorderColor.w < 1.0) shading_flag |= SurfShadingData.FLAG_TRANSPARENT;
    }

    const buffers = if (canvas != null) &self.mOverlayData else &self.mGameData;
    const quad_buff_base = &buffers.mQuadBufferBase;
    const clip_index = try buffers.ClipIndex(engine_context.EngineAllocator(), clip);

    try quad_buff_base.append(engine_context.EngineAllocator(), .{
        .Position = box.Center.ToArray(),
        .Rotation = box.Rotation.ToArray(),
        .HalfExtents = box.HalfExtents.ToArray(),
        .ShadingHandle = @intCast(shading_handle),
        .ShadingFlags = shading_flag,
        .BorderShadingHandle = @intCast(border_shading_handle),
        .BorderWidth = box.BorderWidth,
        .CornerRadii = box.CornerRadii.ToArray(),
        .ClipIndex = clip_index,
    });
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
    if (text_component.mTexOptions.mIsTransparent) texture_shading_flags |= SurfShadingData.FLAG_TRANSPARENT;

    //the text's own position and rotation, in canvas units for an overlay scene
    const text_pos = transform_component.GetWorldPosition();
    const text_rot = transform_component.GetWorldRotation();

    //every glyph turns with the text, and with the canvas on top of that
    const glyph_rot = if (canvas) |c| c.ToWorldRotation(text_rot) else text_rot;
    const size_scale: f32 = if (canvas) |c| c.Scale else 1.0;

    const buffers = if (canvas != null) &self.mOverlayData else &self.mGameData;
    const glyph_buff_base = &buffers.mGlyphBufferBase;
    const clip_index = try buffers.ClipIndex(engine_context.EngineAllocator(), clip);

    //font size and bounds with the text's scale applied, the same ones picking measures the text with
    const params = ShapeGeometry.GetTextParams(transform_component, text_component);

    var layout = TextLayout.Iterator(TextAsset).Init(text_component.mText.items, text_asset, params.FontSize, params.WrapWidth);
    while (layout.Next()) |glyph| {
        //the layout is in the text's own space, so the whole line turns with the transform instead
        //of each glyph turning in place along world x
        const local_pen = Vec3(f32){ .x = glyph.Pen.x - params.LeftBound, .y = glyph.Pen.y, .z = 0 };
        var glyph_pos = text_pos.AddVec(local_pen.QuatRotate(text_rot));
        if (canvas) |c| glyph_pos = c.ToWorldPoint(glyph_pos);
        const half_extents = Vec3(f32){ .x = glyph.HalfExtents.x * size_scale, .y = glyph.HalfExtents.y * size_scale, .z = THICKNESS_2D };
        const plane_center = Vec2(f32){ .x = glyph.PlaneCenter.x * size_scale, .y = glyph.PlaneCenter.y * size_scale };

        //a letter cut off altogether isn't sent
        if (clip) |view_clip| {
            const plane_offset = (Vec3(f32){ .x = plane_center.x, .y = plane_center.y, .z = 0 }).QuatRotate(glyph_rot);
            const glyph_box = ShapeGeometry.Box{ .Center = glyph_pos.AddVec(plane_offset), .Rotation = glyph_rot, .HalfExtents = half_extents };
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

        try glyph_buff_base.append(engine_context.EngineAllocator(), .{
            .Position = glyph_pos.ToArray(),
            .Rotation = glyph_rot.ToVector(),
            .HalfExtents = half_extents.ToArray(),
            .PlaneCenter = plane_center.ToArray(),
            .AtlasShadingHandle = @intCast(atlas_shading_handle),
            .TextureShadingFlags = @intCast(texture_shading_flags),
            .ClipIndex = clip_index,
        });
    }
}
