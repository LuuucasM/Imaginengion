const std = @import("std");
const builtin = @import("builtin");
const SSBO = @import("../SSBOs/SSBO.zig");
const sdl = @import("../Core/CImports.zig").sdl;
const VertexArray = @import("../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const UniformBuffer = @import("../UniformBuffers/UniformBuffer.zig");
const AssetHandle = @import("../ECSObjects/AssetHandle.zig");
const IndexBuffer = @import("../IndexBuffers/IndexBuffer.zig");
const EngineContext = @import("../Core/EngineContext.zig");
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
const EntitySceneComponent = EntityComponents.EntitySceneComponent;

const SceneComponents = @import("../ECSComponents/SComponents.zig");
const SceneSceneComponent = SceneComponents.SceneComponent;

const StorageBufferBinding = @import("RenderPlatform.zig").StorageBufferBinding;
const TextLayout = @import("TextLayout.zig");

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
};

pub const GlyphData = extern struct {
    Rotation: if (is_spirv) Vec4(f32).VectorT else Vec4(f32).ArrayT,
    Position: if (is_spirv) Vec3(f32).VectorT else Vec3(f32).ArrayT,
    HalfExtents: if (is_spirv) Vec3(f32).VectorT else Vec3(f32).ArrayT align(16),
    PlaneCenter: if (is_spirv) Vec2(f32).VectorT else Vec2(f32).ArrayT align(16),
    AtlasShadingHandle: u32,
    TextureShadingFlags: u32,
};

comptime {
    GPUAsserts.AssertGPULayout(QuadData);
    GPUAsserts.AssertGPULayout(GlyphData);
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

    pub fn Init(self: *RenderBuffers, engine_context: *EngineContext) !void {
        self.mQuadBuffer.Init(engine_context, @sizeOf(QuadData) * 100, 2, .Compute);
        self.mQuadBufferBase = try std.ArrayList(QuadData).initCapacity(engine_context.EngineAllocator(), 100);

        self.mGlyphBuffer.Init(engine_context, @sizeOf(GlyphData) * 100, 3, .Compute);
        self.mGlyphBufferBase = try std.ArrayList(GlyphData).initCapacity(engine_context.EngineAllocator(), 100);
    }
    pub fn Deinit(self: *RenderBuffers, engine_context: *EngineContext) void {
        self.mQuadBuffer.Deinit(engine_context);
        self.mQuadBufferBase.deinit(engine_context.EngineAllocator());

        self.mGlyphBuffer.Deinit(engine_context);
        self.mGlyphBufferBase.deinit(engine_context.EngineAllocator());
    }
    pub fn Reset(self: *RenderBuffers, engine_allocator: std.mem.Allocator, reset_options: ResetOptions) void {
        switch (reset_options) {
            .ClearAndFree => {
                self.mQuadBufferBase.clearAndFree(engine_allocator);
                self.mGlyphBufferBase.clearAndFree(engine_allocator);
            },
            .ClearRetainingCapacity => {
                self.mQuadBufferBase.clearRetainingCapacity();
                self.mGlyphBufferBase.clearRetainingCapacity();
            },
        }
    }
    pub fn SetBuffers(self: *RenderBuffers, world_type: EngineContext.WorldType, engine_context: *EngineContext) !void {
        const zone = Tracy.ZoneInit("Renderer2D::SetBuffers", @src());
        defer zone.Deinit();

        const quad_byte_size = self.mQuadBufferBase.items.len * @sizeOf(QuadData);
        const glyph_byte_size = self.mGlyphBufferBase.items.len * @sizeOf(GlyphData);

        //quads
        _ = self.mQuadBuffer.SetData(engine_context, self.mQuadBufferBase.items.ptr, quad_byte_size, 0);

        //glyphs
        _ = self.mGlyphBuffer.SetData(engine_context, self.mGlyphBufferBase.items.ptr, glyph_byte_size, 0);
        //fill out stats
        switch (world_type) {
            .Game => {
                engine_context.mEngineStats.GameWorldStats.mRenderStats.OutputQuadNum = @intCast(self.mQuadBufferBase.items.len);
                engine_context.mEngineStats.GameWorldStats.mRenderStats.OutputGlyphNum = @intCast(self.mGlyphBufferBase.items.len);
            },
            .Editor => {
                engine_context.mEngineStats.EditorWorldStats.mRenderStats.OutputQuadNum = @intCast(self.mQuadBufferBase.items.len);
                engine_context.mEngineStats.EditorWorldStats.mRenderStats.OutputGlyphNum = @intCast(self.mGlyphBufferBase.items.len);
            },
            .Simulate => {
                engine_context.mEngineStats.SimulateWorldStats.mRenderStats.OutputQuadNum = @intCast(self.mQuadBufferBase.items.len);
                engine_context.mEngineStats.SimulateWorldStats.mRenderStats.OutputGlyphNum = @intCast(self.mGlyphBufferBase.items.len);
            },
        }
    }
    pub fn BindBuffers(self: RenderBuffers, render_pass: *anyopaque) void {
        self.mQuadBuffer.Bind(render_pass);
        self.mGlyphBuffer.Bind(render_pass);
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

pub fn SetBuffers(self: *Renderer2D, world_type: EngineContext.WorldType, engine_context: *EngineContext, pipeline_t: PipelineType) !void {
    try switch (pipeline_t) {
        .GamePipeline => self.mGameData.SetBuffers(world_type, engine_context),
        .OverlayPipeline => self.mOverlayData.SetBuffers(world_type, engine_context),
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
    entity_scene_comp: *EntitySceneComponent,
    shading_buff: *ShadingBuffers,
) !void {
    const texture_asset = try quad_component.mTexture.GetAsset(engine_context, Texture2D);
    const scene_scene_comp = entity_scene_comp.mScene.GetComponent(SceneSceneComponent).?;

    const world_pos = transform_component.GetWorldPosition();
    const world_rot = transform_component.GetWorldRotation();
    const world_scale = transform_component.GetWorldScale();

    const shading_handle = try shading_buff.AddSurface(
        engine_context.EngineAllocator(),
        &quad_component.mTexOptions,
        texture_asset,
        std.math.maxInt(u32),
    );

    var shading_flag: u32 = 0;
    if (quad_component.mTexOptions.mIsTransparent) shading_flag |= SurfShadingData.FLAG_TRANSPARENT;

    const quad_buff_base = switch (scene_scene_comp.mLayerType) {
        .GameLayer => &self.mGameData.mQuadBufferBase,
        .OverlayLayer => &self.mOverlayData.mQuadBufferBase,
    };

    try quad_buff_base.append(engine_context.EngineAllocator(), .{
        .Position = world_pos.ToArray(),
        .Rotation = world_rot.ToArray(),
        .HalfExtents = Vec3(f32).ArrayT{ world_scale.x * 0.5, world_scale.y * 0.5, THICKNESS_2D },
        .ShadingHandle = @intCast(shading_handle),
        .ShadingFlags = shading_flag,
    });
}

pub fn DrawText(
    self: *Renderer2D,
    engine_context: *EngineContext,
    transform_component: *EntityTransformComponent,
    text_component: *TextComponent,
    entity_scene_comp: *EntitySceneComponent,
    shading_buff: *ShadingBuffers,
) !void {
    const zone = Tracy.ZoneInit("Renderer2D::DrawText", @src());
    defer zone.Deinit();

    const text_asset = try text_component.mTextAssetHandle.GetAsset(engine_context, TextAsset);
    const atlas_asset = &text_asset.mAtlas;
    const texture_asset = try text_component.mTexHandle.GetAsset(engine_context, Texture2D);
    const scene_scene_comp = entity_scene_comp.mScene.GetComponent(SceneSceneComponent).?;

    const texture_shading_handle = try shading_buff.AddSurface(
        engine_context.EngineAllocator(),
        &text_component.mTexOptions,
        texture_asset,
        std.math.maxInt(u32),
    );

    var texture_shading_flags: u32 = 0;
    if (text_component.mTexOptions.mIsTransparent) texture_shading_flags |= SurfShadingData.FLAG_TRANSPARENT;

    const world_pos = transform_component.GetWorldPosition();
    const world_rot = transform_component.GetWorldRotation();

    const glyph_buff_base = switch (scene_scene_comp.mLayerType) {
        .GameLayer => &self.mGameData.mGlyphBufferBase,
        .OverlayLayer => &self.mOverlayData.mGlyphBufferBase,
    };

    //mBounds is how far the text runs left (x) and right (y) of the transform. layout starts its
    //lines at x = 0, so each line is shifted left by the left bound
    const left_bound = text_component.mBounds.x;
    const wrap_width = text_component.mBounds.x + text_component.mBounds.y;

    var layout = TextLayout.Iterator(TextAsset).Init(text_component.mText.items, text_asset, text_component.mFontSize, wrap_width);
    while (layout.Next()) |glyph| {
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

        //the layout is in the text's own space, so the whole line turns with the transform instead
        //of each glyph turning in place along world x
        const local_pen = Vec3(f32){ .x = glyph.Pen.x - left_bound, .y = glyph.Pen.y, .z = 0 };
        const glyph_pos = world_pos.AddVec(local_pen.QuatRotate(world_rot));

        try glyph_buff_base.append(engine_context.EngineAllocator(), .{
            .Position = glyph_pos.ToArray(),
            .Rotation = world_rot.ToVector(),
            .HalfExtents = Vec3(f32).ArrayT{ glyph.HalfExtents.x, glyph.HalfExtents.y, THICKNESS_2D },
            .PlaneCenter = Vec2(f32).ArrayT{ glyph.PlaneCenter.x, glyph.PlaneCenter.y },
            .AtlasShadingHandle = @intCast(atlas_shading_handle),
            .TextureShadingFlags = @intCast(texture_shading_flags),
        });
    }
}
