const std = @import("std");
const SSBO = @import("../SSBOs/SSBO.zig");
const sdl = @import("../Core/CImports.zig").sdl;
const VertexArray = @import("../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const UniformBuffer = @import("../UniformBuffers/UniformBuffer.zig");
const AssetHandle = @import("../Assets/AssetHandle.zig");
const IndexBuffer = @import("../IndexBuffers/IndexBuffer.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const PipelineType = @import("RenderPipeline.zig").PipelineType;
const ShadingBuffers = @import("Renderer.zig").ShadingBuffers;
const EShadingFlags = @import("Renderer.zig").EShadingFlags;

const Assets = @import("../Assets/Assets.zig");
const Texture2D = Assets.Texture2D;
const TextAsset = Assets.TextAsset;

const MathTypes = @import("../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;
const Vec4 = MathTypes.Vec4;
const Quat = MathTypes.Quat;
const Mat4 = MathTypes.Mat4;

const THICKNESS_2D = @import("../Math/SDFFunctions.zig").THICKNESS_2D;

const EntityComponents = @import("../GameObjects/Components.zig");
const EntityTransformComponent = EntityComponents.TransformComponent;
const QuadComponent = EntityComponents.QuadComponent;
const TextComponent = EntityComponents.TextComponent;
const EntitySceneComponent = EntityComponents.EntitySceneComponent;

const SceneComponents = @import("../Scene/SceneComponents.zig");
const SceneSceneComponent = SceneComponents.SceneComponent;

const StorageBufferBinding = @import("RenderPlatform.zig").StorageBufferBinding;

const Tracy = @import("../Core/Tracy.zig");

const Renderer2D = @This();

const MAX_PATH_LEN = 256;

pub const QuadData = extern struct {
    Rotation: Vec4(f32).VectorT,
    Position: Vec3(f32).VectorT,
    HalfExtents: Vec3(f32).VectorT,
    ShadingHandle: u32,
    ShadingFlags: u32,
};

pub const GlyphData = extern struct {
    Rotation: Vec4(f32).VectorT,
    Position: Vec3(f32).VectorT,
    HalfExtents: Vec3(f32).VectorT,
    PlaneCenter: Vec2(f32).VectorT,
    AtlasShadingHandle: u32,
    TextureShadingFlags: u32,
};

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
        self.mQuadBuffer.Init(engine_context, @sizeOf(QuadData) * 100, 2, .Fragment);
        self.mQuadBufferBase = try std.ArrayList(QuadData).initCapacity(engine_context.EngineAllocator(), 100);

        self.mGlyphBuffer.Init(engine_context, @sizeOf(GlyphData) * 100, 3, .Fragment);
        self.mGlyphBufferBase = try std.ArrayList(GlyphData).initCapacity(engine_context.EngineAllocator(), 100);
    }
    pub fn Deinit(self: *RenderBuffers, engine_context: *EngineContext) void {
        self.mQuadBuffer.Deinit(engine_context);
        self.mQuadBufferBase.deinit(engine_context.EngineAllocator());

        self.mGlyphBuffer.Deinit(engine_context);
        self.mGlyphBufferBase.deinit(engine_context.EngineAllocator());
    }
    pub fn ClearAndFree(self: *RenderBuffers, engine_allocator: std.mem.Allocator) void {
        self.mQuadBufferBase.clearAndFree(engine_allocator);
        self.mGlyphBufferBase.clearAndFree(engine_allocator);
    }
    pub fn SetBuffers(self: *RenderBuffers, world_type: EngineContext.WorldType, engine_context: *EngineContext) !void {
        const zone = Tracy.ZoneInit("R2D SetBuffers", @src());
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
    self.mGameData.ClearAndFree(engine_allocator);
    self.mOverlayData.ClearAndFree(engine_allocator);
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
    const zone = Tracy.ZoneInit("R2D DrawQuad", @src());
    defer zone.Deinit();

    const texture_asset = try quad_component.mTexture.GetAsset(engine_context, Texture2D);
    const scene_scene_comp = entity_scene_comp.mScene.GetComponent(SceneSceneComponent).?;

    const world_pos = transform_component.GetWorldPosition();
    const world_rot = transform_component.GetWorldRotation();
    const world_scale = transform_component.GetWorldScale();

    const shading_handle = shading_buff.AddSurface(
        engine_context.EngineAllocator(),
        quad_component.mTexOptions.mTilingFactor,
        quad_component.mTexOptions.mTextureUV0,
        quad_component.mTexOptions.mTextureUV1,
        quad_component.mTexOptions.mTilingFactor,
        texture_asset.GetTextureHandle(),
        std.math.maxInt(u32),
    );

    var shading_flag: u32 = 0;
    if (quad_component.mMaterial.mOpaqueMode == .Transparent) shading_flag |= EShadingFlags.SURFACE_TRANSPARENT.ToInt();

    switch (scene_scene_comp.mLayerType) {
        .GameLayer => try self.mGameData.mQuadBufferBase.append(engine_context.EngineAllocator(), .{
            .Position = world_pos.ToVector(),
            .Rotation = world_rot.ToVector(),
            .HalfExtents = Vec3(f32).VectorT{ world_scale.x * 0.5, world_scale.y * 0.5, THICKNESS_2D },
            .ShadingHandle = @intCast(shading_handle),
            .ShadingFlags = shading_flag,
        }),
        .OverlayLayer => try self.mGameData.mQuadBufferBase.append(engine_context.EngineAllocator(), .{
            .Position = world_pos.ToVector(),
            .Rotation = world_rot.ToVector(),
            .HalfExtents = Vec3(f32).VectorT{ world_scale.x * 0.5, world_scale.y * 0.5, THICKNESS_2D },
            .ShadingHandle = @intCast(shading_handle),
            .ShadingFlags = shading_flag,
        }),
    }
}

pub fn DrawText(
    self: *Renderer2D,
    engine_context: *EngineContext,
    transform_component: *EntityTransformComponent,
    text_component: *TextComponent,
    entity_scene_comp: *EntitySceneComponent,
    shading_buff: *ShadingBuffers,
) !void {
    const zone = Tracy.ZoneInit("R2D DrawQuad", @src());
    defer zone.Deinit();

    const text_asset = try text_component.mTextAssetHandle.GetAsset(engine_context, TextAsset);
    const atlas_asset = text_asset.mAtlas;
    const texture_asset = try text_component.mTexHandle.GetAsset(engine_context, Texture2D);
    const scene_scene_comp = entity_scene_comp.mScene.GetComponent(SceneSceneComponent).?;

    const texture_shading_handle = shading_buff.AddSurface(
        engine_context.EngineAllocator(),
        text_component.mTexOptions.mColor,
        text_component.mTexOptions.mTextureUV0,
        text_component.mTexOptions.mTextureUV1,
        text_component.mTexOptions.mTilingFactor,
        texture_asset.GetTextureHandle(),
        std.math.maxInt(u32),
    );

    var texture_shading_flags: u32 = 0;
    if (text_component.mMaterial.mOpaqueMode == .Transparent) texture_shading_flags |= EShadingFlags.SURFACE_TRANSPARENT.ToInt();

    const world_pos = transform_component.GetWorldPosition();

    const left_bounds = world_pos.x - text_component.mBounds.x;
    const right_bounds = world_pos.x + text_component.mBounds.y;

    var pen_x = left_bounds;
    var pen_y = world_pos.y;

    for (text_component.mText.items, 0..) |char, i| {
        const array_ind = TextAsset.ToArrayIndex(char);
        const glyph = text_asset.mGlyphs[array_ind];

        if (char == 32) { //if its space just continue on
            pen_x += glyph.mAdvance * text_component.mFontSize;
            continue;
        }

        const glyph_width = glyph.mAdvance;

        if (pen_x + glyph_width > right_bounds) {
            pen_x = left_bounds;
            pen_y -= (text_asset.mLineHeight * text_component.mFontSize);
        }

        const atlas_shading_handle = shading_buff.AddSurface(
            engine_context.EngineAllocator(),
            Vec4(f32).VectorT{ 1.0, 1.0, 1.0, 1.0 },
            (glyph.mAtlasTexel0.ToVector() / text_asset.mAtlasSize.ToVector()),
            (glyph.mAtlasTexel1.ToVector() / text_asset.mAtlasSize.ToVector()),
            1.0,
            atlas_asset.GetTextureHandle(),
            texture_shading_handle,
        );

        const left = glyph.mPlaneMin.x;
        const top = glyph.mPlaneMin.y;
        const right = glyph.mPlaneMax.x;
        const bottom = glyph.mPlaneMax.y;

        const plane_size: Vec2(f32) = .{
            .x = (right - left) * text_component.mFontSize,
            .y = (top - bottom) * text_component.mFontSize,
        };

        const plane_center: Vec2(f32) = .{
            .x = (left + right) * 0.5 * text_component.mFontSize,
            .y = (top + bottom) * 0.5 * text_component.mFontSize,
        };

        switch (scene_scene_comp.mLayerType) {
            .GameLayer => try self.mGameData.mGlyphBufferBase.append(engine_context.FrameAllocator(), .{
                .Position = Vec3(f32).VectorT{ pen_x, pen_y, world_pos.z },
                .Rotation = transform_component.Rotation.ToVector(),
                .HalfExtents = Vec3(f32).VectorT{ plane_size.x * 0.5, plane_size.y * 0.5, THICKNESS_2D },
                .PlaneCenter = Vec2(f32).VectorT{ plane_center.x, plane_center.y },
                .AtlasShadingHandle = atlas_shading_handle,
                .TextureShadingFlags = texture_shading_flags,
            }),
            .OverlayLayer => try self.mOverlayData.mGlyphBufferBase.append(engine_context.FrameAllocator(), .{
                .Position = Vec3(f32).VectorT{ pen_x, pen_y, world_pos.z },
                .Rotation = transform_component.Rotation.ToVector(),
                .HalfExtents = Vec3(f32).VectorT{ plane_size.x * 0.5, plane_size.y * 0.5, THICKNESS_2D },
                .PlaneCenter = Vec2(f32).VectorT{ plane_center.x, plane_center.y },
                .AtlasShadingHandle = atlas_shading_handle, //
                .TextureShadingFlags = texture_shading_flags,
            }),
        }

        var move_dist = glyph_width;
        if (i < text_component.mText.items.len - 1) {
            if (glyph.mKernings.get(text_component.mText.items[i + 1])) |kerning_advance| {
                move_dist += kerning_advance;
            }
        }

        pen_x += (move_dist) * text_component.mFontSize;
    }
}
