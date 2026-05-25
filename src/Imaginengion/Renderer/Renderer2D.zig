const std = @import("std");
const SSBO = @import("../SSBOs/SSBO.zig");
const sdl = @import("../Core/CImports.zig").sdl;
const VertexArray = @import("../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const UniformBuffer = @import("../UniformBuffers/UniformBuffer.zig");
const AssetHandle = @import("../Assets/AssetHandle.zig");
const IndexBuffer = @import("../IndexBuffers/IndexBuffer.zig");
const EngineContext = @import("../Core/EngineContext.zig");

const Assets = @import("../Assets/Assets.zig");
const Texture2D = Assets.Texture2D;
const TextAsset = Assets.TextAsset;

const MathTypes = @import("../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;
const Vec4 = MathTypes.Vec4;
const Quat = MathTypes.Quat;
const Mat4 = MathTypes.Mat4;

const EntityComponents = @import("../GameObjects/Components.zig");
const EntityTransformComponent = EntityComponents.TransformComponent;
const QuadComponent = EntityComponents.QuadComponent;
const TextComponent = EntityComponents.TextComponent;

const StorageBufferBinding = @import("RenderPlatform.zig").StorageBufferBinding;

const Tracy = @import("../Core/Tracy.zig");

const Renderer2D = @This();

const MAX_PATH_LEN = 256;

pub const QuadData = extern struct {
    Position: Vec3(f32).VectorT,
    _pad0: f32 = 0,
    Rotation: Vec4(f32).VectorT,
    Scale: Vec3(f32).VectorT,
    _pad1: f32 = 0,

    TilingFactor: f32,
    TextureHandle: u32,
    _pad2: [2]u32 = .{ 0, 0 },

    Color: Vec4(f32).VectorT,
    TextureUV0: Vec2(f32).VectorT,
    TextureUV1: Vec2(f32).VectorT,
};

pub const GlyphData = extern struct {
    Position: Vec3(f32).VectorT,
    Scale: f32,
    Rotation: Vec4(f32).VectorT,

    TilingFactor: f32,
    _pad0: [3]u32 = .{ 0, 0, 0 },
    Color: Vec4(f32).VectorT,

    TextureUV0: Vec2(f32).VectorT,
    TextureUV1: Vec2(f32).VectorT,
    AtlasUV0: Vec2(f32).VectorT, // atlas left,bottom
    AtlasUV1: Vec2(f32).VectorT, // atlas right,top
    PlaneMin: Vec2(f32).VectorT, // plane left,bottom
    PlaneMax: Vec2(f32).VectorT, // plane right,top

    AtlasHandle: u32,
    TextureHandle: u32,
    _pad1: [2]u32 = .{ 0, 0 },
};

mQuadBuffer: SSBO = .{},
mQuadBufferBase: std.ArrayList(QuadData) = .empty,

mGlyphBuffer: SSBO = .{},
mGlyphBufferBase: std.ArrayList(GlyphData) = .empty,

pub fn Init(self: *Renderer2D, engine_context: *EngineContext) !void {
    self.mQuadBuffer.Init(engine_context, @sizeOf(QuadData) * 100, 0, .Fragment);
    self.mQuadBufferBase = try std.ArrayList(QuadData).initCapacity(engine_context.EngineAllocator(), 100);

    self.mGlyphBuffer.Init(engine_context, @sizeOf(GlyphData) * 100, 1, .Fragment);
    self.mGlyphBufferBase = try std.ArrayList(GlyphData).initCapacity(engine_context.EngineAllocator(), 100);
}

pub fn Deinit(self: *Renderer2D, engine_context: *EngineContext) void {
    self.mQuadBuffer.Deinit(engine_context);
    self.mQuadBufferBase.deinit(engine_context.EngineAllocator());

    self.mGlyphBuffer.Deinit(engine_context);
    self.mGlyphBufferBase.deinit(engine_context.EngineAllocator());
}

pub fn StartBatch(self: *Renderer2D, engine_allocator: std.mem.Allocator) void {
    self.mQuadBufferBase.clearAndFree(engine_allocator);
    self.mGlyphBufferBase.clearAndFree(engine_allocator);
}

pub fn SetBuffers(self: *Renderer2D, world_type: EngineContext.WorldType, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("R2D SetBuffers", @src());
    defer zone.Deinit();

    const quad_byte_size = self.mQuadBufferBase.items.len * @sizeOf(QuadData);
    const glyph_byte_size = self.mGlyphBufferBase.items.len * @sizeOf(GlyphData);

    //quads
    _ = self.mQuadBuffer.SetData(engine_context, self.mQuadBufferBase.items.ptr, quad_byte_size, 0);

    //glyphs
    _ = self.mGlyphBuffer.SetData(engine_context, self.mGlyphBufferBase.items.ptr, glyph_byte_size, 0);
    //more shape

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

pub fn BindBuffers(self: Renderer2D, render_pass: *anyopaque) void {
    self.mQuadBuffer.Bind(render_pass);
    self.mGlyphBuffer.Bind(render_pass);
}

pub fn GetQuadCount(self: Renderer2D) u32 {
    return @intCast(self.mQuadBufferBase.items.len);
}

pub fn GetGlyphCount(self: Renderer2D) u32 {
    return @intCast(self.mGlyphBufferBase.items.len);
}

pub fn GetQuadsBuffer(self: *Renderer2D) *anyopaque {
    return self.mQuadBuffer.GetBuffer().?;
}

pub fn GetGlyphsBuffer(self: *Renderer2D) *anyopaque {
    return self.mGlyphBuffer.GetBuffer().?;
}

pub fn DrawQuad(self: *Renderer2D, engine_context: *EngineContext, transform_component: *EntityTransformComponent, quad_component: *QuadComponent) !void {
    const zone = Tracy.ZoneInit("R2D DrawQuad", @src());
    defer zone.Deinit();

    const texture_asset = try quad_component.mTexture.GetAsset(engine_context, Texture2D);

    const world_pos = transform_component.GetWorldPosition();
    const world_rot = transform_component.GetWorldRotation();
    const world_scale = transform_component.GetWorldScale();

    try self.mQuadBufferBase.append(engine_context.EngineAllocator(), .{
        .Position = world_pos.ToVector(),
        .Rotation = world_rot.ToVector(),
        .Scale = world_scale.ToVector(),
        .TextureHandle = texture_asset.GetTextureHandle(),
        .Color = quad_component.mTexOptions.mColor.ToVector(),
        .TextureUV0 = quad_component.mTexOptions.mTextureUV0.ToVector(),
        .TextureUV1 = quad_component.mTexOptions.mTextureUV1.ToVector(),
        .TilingFactor = quad_component.mTexOptions.mTilingFactor,
    });
}

pub fn DrawText(self: *Renderer2D, engine_context: *EngineContext, transform_component: *EntityTransformComponent, text_component: *TextComponent) !void {
    const zone = Tracy.ZoneInit("R2D DrawQuad", @src());
    defer zone.Deinit();

    const text_asset = try text_component.mTextAssetHandle.GetAsset(engine_context, TextAsset);
    const atlas_asset = text_asset.mAtlas;
    const texture_asset = try text_component.mTexHandle.GetAsset(engine_context, Texture2D);

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

        try self.mGlyphBufferBase.append(engine_context.FrameAllocator(), .{
            .Position = Vec3(f32).VectorT{ pen_x, pen_y, world_pos.z },
            .Rotation = transform_component.Rotation.ToVector(),
            .Scale = text_component.mFontSize,

            .TextureUV0 = text_component.mTexOptions.mTextureUV0.ToVector(),
            .TextureUV1 = text_component.mTexOptions.mTextureUV1.ToVector(),
            .AtlasUV0 = glyph.mAtlasUV0.ToVector(),
            .AtlasUV1 = glyph.mAtlasUV1.ToVector(),
            .PlaneMin = glyph.mPlaneMin.ToVector(),
            .PlaneMax = glyph.mPlaneMax.ToVector(),

            .AtlasHandle = atlas_asset.GetTextureHandle(),
            .TextureHandle = texture_asset.GetTextureHandle(),
            .Color = text_component.mTexOptions.mColor.ToVector(),
            .TilingFactor = text_component.mTexOptions.mTilingFactor,
        });

        var move_dist = glyph_width;
        if (i < text_component.mText.items.len - 1) {
            if (glyph.mKernings.get(text_component.mText.items[i + 1])) |kerning_advance| {
                move_dist += kerning_advance;
            }
        }

        pen_x += (move_dist) * text_component.mFontSize;
    }
}
