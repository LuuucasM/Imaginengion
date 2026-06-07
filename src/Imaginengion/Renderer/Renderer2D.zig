const std = @import("std");
const SSBO = @import("../SSBOs/SSBO.zig");
const sdl = @import("../Core/CImports.zig").sdl;
const VertexArray = @import("../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const UniformBuffer = @import("../UniformBuffers/UniformBuffer.zig");
const AssetHandle = @import("../Assets/AssetHandle.zig");
const IndexBuffer = @import("../IndexBuffers/IndexBuffer.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const ShadingData = @import("Renderer.zig").ShadingData;
const PipelineType = @import("RenderPipeline.zig").PipelineType;

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
    Position: Vec3(f32).VectorT,
    ShadingHandle: u32,
    Rotation: Vec4(f32).VectorT,
    HalfExtents: Vec4(f32).VectorT,
    ShadingFlags: u32,
};

pub const GlyphData = extern struct {
    Position: Vec3(f32).VectorT,
    AtlasShadingHandle: u32,
    Rotation: Vec4(f32).VectorT,
    HalfExtents: Vec3(f32).VectorT,
    PlaneCenter: Vec2(f32).VectorT,
    TextureShadingHandle: u32,
    AtlasShadingFlags: u32,
    TextureShadingFlags: u32,
    _pad0: f32 = 9,
};

pub const BufferKind = enum {
    Quad,
    Glyph,
    Shading,
};

pub const ShaderData = struct {
    mQuadBuffer: SSBO = .{},
    mQuadBufferBase: std.ArrayList(QuadData) = .empty,

    mGlyphBuffer: SSBO = .{},
    mGlyphBufferBase: std.ArrayList(GlyphData) = .empty,

    mShadingBuffer: SSBO = .{},
    mShadingBufferBase: std.ArrayList(ShadingData) = .empty,

    pub fn Init(self: *ShaderData, engine_context: *EngineContext) !void {
        self.mQuadBuffer.Init(engine_context, @sizeOf(QuadData) * 100, 2, .Fragment);
        self.mQuadBufferBase = try std.ArrayList(QuadData).initCapacity(engine_context.EngineAllocator(), 100);

        self.mGlyphBuffer.Init(engine_context, @sizeOf(GlyphData) * 100, 3, .Fragment);
        self.mGlyphBufferBase = try std.ArrayList(GlyphData).initCapacity(engine_context.EngineAllocator(), 100);

        self.mShadingBuffer.Init(engine_context, @sizeOf(ShadingData) * 100, 4, .Fragment);
        self.mShadingBufferBase = try std.ArrayList(ShadingData).initCapacity(engine_context.EngineAllocator(), 100);
    }
    pub fn Deinit(self: *ShaderData, engine_context: *EngineContext) void {
        self.mQuadBuffer.Deinit(engine_context);
        self.mQuadBufferBase.deinit(engine_context.EngineAllocator());

        self.mGlyphBuffer.Deinit(engine_context);
        self.mGlyphBufferBase.deinit(engine_context.EngineAllocator());

        self.mShadingBuffer.Deinit(engine_context);
        self.mShadingBufferBase.deinit(engine_context.EngineAllocator());
    }
    pub fn ClearAndFree(self: *ShaderData, engine_allocator: std.mem.Allocator) void {
        self.mQuadBufferBase.clearAndFree(engine_allocator);
        self.mGlyphBufferBase.clearAndFree(engine_allocator);
        self.mShadingBufferBase.clearAndFree(engine_allocator);
    }
    pub fn SetBuffers(self: *ShaderData, world_type: EngineContext.WorldType, engine_context: *EngineContext) !void {
        const zone = Tracy.ZoneInit("R2D SetBuffers", @src());
        defer zone.Deinit();

        const quad_byte_size = self.mQuadBufferBase.items.len * @sizeOf(QuadData);
        const glyph_byte_size = self.mGlyphBufferBase.items.len * @sizeOf(GlyphData);
        const shading_byte_size = self.mShadingBufferBase.items.len * @sizeOf(ShadingData);

        //quads
        _ = self.mQuadBuffer.SetData(engine_context, self.mQuadBufferBase.items.ptr, quad_byte_size, 0);

        //glyphs
        _ = self.mGlyphBuffer.SetData(engine_context, self.mGlyphBufferBase.items.ptr, glyph_byte_size, 0);

        //shadings
        _ = self.mShadingBuffer.SetData(engine_context, self.mShadingBufferBase.items.ptr, shading_byte_size, 0);

        //fill out stats
        switch (world_type) {
            .Game => {
                engine_context.mEngineStats.GameWorldStats.mRenderStats.OutputQuadNum = @intCast(self.mQuadBufferBase.items.len);
                engine_context.mEngineStats.GameWorldStats.mRenderStats.OutputGlyphNum = @intCast(self.mGlyphBufferBase.items.len);
                engine_context.mEngineStats.GameWorldStats.mRenderStats.ShadingsNum = @intCast(self.mShadingBufferBase.items.len);
            },
            .Editor => {
                engine_context.mEngineStats.EditorWorldStats.mRenderStats.OutputQuadNum = @intCast(self.mQuadBufferBase.items.len);
                engine_context.mEngineStats.EditorWorldStats.mRenderStats.OutputGlyphNum = @intCast(self.mGlyphBufferBase.items.len);
                engine_context.mEngineStats.EditorWorldStats.mRenderStats.ShadingsNum = @intCast(self.mGlyphBufferBase.items.len);
            },
            .Simulate => {
                engine_context.mEngineStats.SimulateWorldStats.mRenderStats.OutputQuadNum = @intCast(self.mQuadBufferBase.items.len);
                engine_context.mEngineStats.SimulateWorldStats.mRenderStats.OutputGlyphNum = @intCast(self.mGlyphBufferBase.items.len);
                engine_context.mEngineStats.SimulateWorldStats.mRenderStats.ShadingsNum = @intCast(self.mShadingBufferBase.items.len);
            },
        }
    }
    pub fn BindBuffers(self: ShaderData, render_pass: *anyopaque) void {
        self.mQuadBuffer.Bind(render_pass);
        self.mGlyphBuffer.Bind(render_pass);
        self.mShadingBuffer.Bind(render_pass);
    }
};

mGameData: ShaderData = .{},
mOverlayData: ShaderData = .{},

pub fn Init(self: *Renderer2D, engine_context: *EngineContext) !void {
    try self.mGameData.Init(engine_context);
    try self.mOverlayData.Init(engine_context);
}

pub fn Deinit(self: *Renderer2D, engine_context: *EngineContext) void {
    self.mGameData.Deinit(engine_context);
    self.mOverlayData.Init(engine_context);
}

pub fn StartBatch(self: *Renderer2D, engine_allocator: std.mem.Allocator) void {
    self.mGameData.ClearAndFree(engine_allocator);
    self.mOverlayData.ClearAndFree(engine_allocator);
}

pub fn SetBuffers(self: *Renderer2D, world_type: EngineContext.WorldType, engine_context: *EngineContext, pipeline_t: PipelineType) !void {
    switch (pipeline_t) {
        .GameShader => self.mGameData.SetBuffers(world_type, engine_context),
        .OverlayShader => self.mOverlayData.SetBuffers(world_type, engine_context),
    }
}

pub fn BindBuffers(self: Renderer2D, render_pass: *anyopaque, pipeline_t: PipelineType) void {
    switch (pipeline_t) {
        .GameShader => self.mGameData.BindBuffers(render_pass),
        .OverlayShader => self.mOverlayData.BindBuffers(render_pass),
    }
}

pub fn GetBufferCount(self: Renderer2D, comptime buff_kind: BufferKind, pipeline_kind: PipelineType) u32 {
    return switch (pipeline_kind) {
        .GameShader => switch (buff_kind) {
            .Quad => @intCast(self.mGameData.mQuadBufferBase.items.len),
            .Glyph => @intCast(self.mGameData.mGlyphBufferBase.items.len),
            .Shading => @intCast(self.mGameData.mShadingBufferBase.items.len),
        },
        .OverlayShader => switch (buff_kind) {
            .Quad => @intCast(self.mOverlayData.mQuadBufferBase.items.len),
            .Glyph => @intCast(self.mOverlayData.mGlyphBufferBase.items.len),
            .Shading => @intCast(self.mOverlayData.mShadingBufferBase.items.len),
        },
    };
}

pub fn GetBuffer(self: Renderer2D, comptime buff_kind: BufferKind, pipeline_kind: PipelineType) *anyopaque {
    return switch (pipeline_kind) {
        .GameShader => switch (buff_kind) {
            .Quad => @intCast(self.mGameData.mQuadBuffer.GetBuffer()),
            .Glyph => @intCast(self.mGameData.mGlyphBuffer.GetBuffer()),
            .Shading => @intCast(self.mGameData.mShadingBuffer.GetBuffer()),
        },
        .OverlayShader => switch (buff_kind) {
            .Quad => @intCast(self.mOverlayData.mQuadBuffer.GetBuffer()),
            .Glyph => @intCast(self.mOverlayData.mGlyphBuffer.GetBuffer()),
            .Shading => @intCast(self.mOverlayData.mShadingBuffer.GetBuffer()),
        },
    };
}

pub fn DrawQuad(self: *Renderer2D, engine_context: *EngineContext, transform_component: *EntityTransformComponent, quad_component: *QuadComponent, entity_scene_comp: EntitySceneComponent) !void {
    const zone = Tracy.ZoneInit("R2D DrawQuad", @src());
    defer zone.Deinit();

    const texture_asset = try quad_component.mTexture.GetAsset(engine_context, Texture2D);
    const scene_scene_comp = entity_scene_comp.mScene.GetComponent(SceneSceneComponent).?;

    const world_pos = transform_component.GetWorldPosition();
    const world_rot = transform_component.GetWorldRotation();
    const world_scale = transform_component.GetWorldScale();

    const shading_handle = switch (scene_scene_comp.mLayerType) {
        .GameLayer => blk: {
            try self.mGameData.mShadingBufferBase.append(engine_context.EngineAllocator(), .{
                .TilingFactor = quad_component.mTexOptions.mTilingFactor,
                .TextureUV0 = quad_component.mTexOptions.mTextureUV0.ToVector(),
                .TextureUV1 = quad_component.mTexOptions.mTextureUV1.ToVector(),
                .Texturehandle = texture_asset.GetTextureHandle(),
                .Color = quad_component.mMaterial.mSurfaceColor.ToVector(),
                .Absorption = quad_component.mMaterial.Absorption.ToVector(),
                .SiblingShading = std.math.maxInt(u32),
            });

            break :blk self.mShadingBufferBase.items.len - 1;
        },
        .OverlayLayer => blk: {
            try self.mOverlayData.mShadingBufferBase.append(engine_context.EngineAllocator(), .{
                .TilingFactor = quad_component.mTexOptions.mTilingFactor,
                .TextureUV0 = quad_component.mTexOptions.mTextureUV0.ToVector(),
                .TextureUV1 = quad_component.mTexOptions.mTextureUV1.ToVector(),
                .Texturehandle = texture_asset.GetTextureHandle(),
                .Color = quad_component.mMaterial.mSurfaceColor.ToVector(),
                .Absorption = quad_component.mMaterial.Absorption.ToVector(),
                .SiblingShading = std.math.maxInt(u32),
            });

            break :blk self.mShadingBufferBase.items.len - 1;
        },
    };

    var shading_flag: u32 = 0;
    if (quad_component.mMaterial.mSurfaceColor.w < 1.0) shading_flag |= ShadingData.SHADING_FLAG_TRANSPARENT;

    switch (scene_scene_comp.mLayerType) {
        .GameLayer => try self.mGameData.mQuadBufferBase.append(engine_context.EngineAllocator(), .{
            .Position = world_pos.ToVector(),
            .Rotation = world_rot.ToVector(),
            .HalfExtents = Vec4(f32).VectorT{ world_scale.x * 0.5, world_scale.y * 0.5, world_scale.z * 0.5, THICKNESS_2D },
            .ShadingHandle = @intCast(shading_handle),
            .ShadingFlags = shading_flag,
        }),
        .OverlayLayer => try self.mGameData.mQuadBufferBase.append(engine_context.EngineAllocator(), .{
            .Position = world_pos.ToVector(),
            .Rotation = world_rot.ToVector(),
            .HalfExtents = Vec4(f32).VectorT{ world_scale.x * 0.5, world_scale.y * 0.5, world_scale.z * 0.5, THICKNESS_2D },
            .ShadingHandle = @intCast(shading_handle),
            .ShadingFlags = shading_flag,
        }),
    }
}

pub fn DrawText(self: *Renderer2D, engine_context: *EngineContext, transform_component: *EntityTransformComponent, text_component: *TextComponent, entity_scene_comp: EntitySceneComponent) !void {
    const zone = Tracy.ZoneInit("R2D DrawQuad", @src());
    defer zone.Deinit();

    const text_asset = try text_component.mTextAssetHandle.GetAsset(engine_context, TextAsset);
    const atlas_asset = text_asset.mAtlas;
    const texture_asset = try text_component.mTexHandle.GetAsset(engine_context, Texture2D);
    const scene_scene_comp = entity_scene_comp.mScene.GetComponent(SceneSceneComponent).?;

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

        const texture_shading_handle = switch (scene_scene_comp.mLayerType) {
            .GameLayer => blk: {
                try self.mGameData.mShadingBufferBase.append(engine_context.EngineAllocator(), .{
                    .TilingFactor = text_component.mTexOptions.mTilingFactor,
                    .TextureUV0 = text_component.mTexOptions.mTextureUV0.ToVector(),
                    .TextureUV1 = text_component.mTexOptions.mTextureUV1.ToVector(),
                    .Texturehandle = texture_asset.GetTextureHandle(),
                    .Color = text_component.mMaterial.mSurfaceColor.ToVector(),
                    .Absorption = text_component.mMaterial.Absorption.ToVector(),
                    .SiblingShading = std.math.maxInt(u32),
                });
                break :blk self.mShadingBufferBase.items.len - 1;
            },
            .OverlayLayer => blk: {
                try self.mOverlayData.mShadingBufferBase.append(engine_context.EngineAllocator(), .{
                    .TilingFactor = text_component.mTexOptions.mTilingFactor,
                    .TextureUV0 = text_component.mTexOptions.mTextureUV0.ToVector(),
                    .TextureUV1 = text_component.mTexOptions.mTextureUV1.ToVector(),
                    .Texturehandle = texture_asset.GetTextureHandle(),
                    .Color = text_component.mMaterial.mSurfaceColor.ToVector(),
                    .Absorption = text_component.mMaterial.Absorption.ToVector(),
                    .SiblingShading = std.math.maxInt(u32),
                });
                break :blk self.mShadingBufferBase.items.len - 1;
            },
        };

        var texture_shading_flags: u32 = 0;
        if (text_component.mMaterial.mSurfaceColor.w < 1.0) texture_shading_flags |= ShadingData.SHADING_FLAG_TRANSPARENT;

        const atlas_shading_handle = switch (scene_scene_comp.mLayerType) {
            .GameLayer => blk: {
                try self.mGameData.mShadingBufferBase.append(engine_context.EngineAllocator(), .{
                    .TilingFactor = 1.0,
                    .TextureUV0 = glyph.mAtlasUV0.ToVector(),
                    .TextureUV1 = glyph.mAtlasUV1.ToVector(),
                    .Texturehandle = atlas_asset.GetTextureHandle(),
                    .Color = Vec4(f32).VectorT{ 1.0, 1.0, 1.0, 1.0 },
                    .Absorption = Vec3(f32).VectorT{ 0.0, 0.0, 0.0 },
                    .SiblingShading = texture_shading_handle,
                });
                break :blk self.mShadingBufferBase.items.len - 1;
            },
            .OverlayLayer => blk: {
                try self.mOverlayData.mShadingBufferBase.append(engine_context.EngineAllocator(), .{
                    .TilingFactor = 1.0,
                    .TextureUV0 = glyph.mAtlasUV0.ToVector(),
                    .TextureUV1 = glyph.mAtlasUV1.ToVector(),
                    .Texturehandle = atlas_asset.GetTextureHandle(),
                    .Color = Vec4(f32).VectorT{ 1.0, 1.0, 1.0, 1.0 },
                    .Absorption = Vec3(f32).VectorT{ 0.0, 0.0, 0.0 },
                    .SiblingShading = texture_shading_handle,
                });
                break :blk self.mShadingBufferBase.items.len - 1;
            },
        };

        const left = glyph.mPlaneMin[0];
        const top = glyph.mPlaneMin[1];
        const right = glyph.mPlaneMax[0];
        const bottom = glyph.mPlaneMax[1];

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
                .AtlasShadingHandle = atlas_shading_handle, //
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
