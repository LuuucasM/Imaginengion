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

const LinAlg = @import("../Math/LinAlg.zig");
const Vec2f32 = LinAlg.Vec2f32;
const Vec3f32 = LinAlg.Vec3f32;
const Vec4f32 = LinAlg.Vec4f32;
const Quatf32 = LinAlg.Quatf32;
const Mat4f32 = LinAlg.Mat4f32;

const EntityComponents = @import("../GameObjects/Components.zig");
const EntityTransformComponent = EntityComponents.TransformComponent;
const QuadComponent = EntityComponents.QuadComponent;
const TextComponent = EntityComponents.TextComponent;

const StorageBufferBinding = @import("RenderPlatform.zig").StorageBufferBinding;

const Tracy = @import("../Core/Tracy.zig");

const Renderer2D = @This();

const MAX_PATH_LEN = 256;

pub const QuadData = extern struct {
    //transform data
    Position: [3]f32,
    _padding0: f32 = 0.0,
    Rotation: [4]f32,
    Scale: [3]f32,

    //texture data
    TilingFactor: f32 = 1.0,
    Color: [4]f32 = [4]f32{ 1.0, 1.0, 1.0, 1.0 },
    TexCoords: [4]f32 = [4]f32{ 0, 0, 1, 1 },
    TexIndex: u32, // 8-byte aligned naturally here
    _padding1: [2]f32 = [2]f32{ 0.0, 0.0 },
};

pub const GlyphData = extern struct {
    //transofmr data
    Position: [3]f32,
    Scale: f32, // Moved here to fill the vec3 padding
    Rotation: [4]f32,

    //texture data
    TilingFactor: f32 = 1.0,
    _padding1: [3]f32 = [3]f32{ 0.0, 0.0, 0.0 },
    Color: [4]f32 = [4]f32{ 1.0, 1.0, 1.0, 1.0 },
    TexCoords: [4]f32 = [4]f32{ 0, 0, 1, 1 },

    AtlasBounds: [4]f32,
    PlaneBounds: [4]f32,
    AtlasIndex: u32, // 8-byte aligned
    TexIndex: u32, // 8-byte aligned
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

    const texture_asset = try quad_component.mTexture.GetTexture(engine_context);

    const world_pos = transform_component.GetWorldPosition();
    const world_rot = transform_component.GetWorldRotation();
    const world_scale = transform_component.GetWorldScale();

    try self.mQuadBufferBase.append(engine_context.EngineAllocator(), .{
        .Position = [3]f32{ world_pos[0], world_pos[1], world_pos[2] },
        .Rotation = [4]f32{ world_rot[0], world_rot[1], world_rot[2], world_rot[3] },
        .Scale = [3]f32{ world_scale[0], world_scale[1], world_scale[2] },
        .TexIndex = texture_asset.GetTextureHandle(),
        .Color = [4]f32{ quad_component.mTexOptions.mColor[0], quad_component.mTexOptions.mColor[1], quad_component.mTexOptions.mColor[2], quad_component.mTexOptions.mColor[3] },
        .TexCoords = [4]f32{ quad_component.mTexOptions.mTexCoords[0], quad_component.mTexOptions.mTexCoords[1], quad_component.mTexOptions.mTexCoords[2], quad_component.mTexOptions.mTexCoords[3] },
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

    const left_bounds = world_pos[0] - text_component.mBounds[0];
    const right_bounds = world_pos[0] + text_component.mBounds[1];

    var pen_x = left_bounds;
    var pen_y = world_pos[1];

    for (text_component.mText.items, 0..) |char, i| {
        const array_ind: usize = TextAsset.ToArrayIndex(char);
        const glyph = text_asset.mGlyphs[array_ind];

        if (char == 32) { //if its space just continue on
            pen_x += glyph.mAdvance * text_component.mFontSize;
            continue;
        }

        const glyph_atlas_bounds = glyph.mAtlasBounds;
        const glyph_plane_bounds = glyph.mPlaneBounds;

        const glyph_width = glyph.mAdvance;

        if (pen_x + glyph_width > right_bounds) {
            pen_x = left_bounds;
            pen_y -= (text_asset.mLineHeight * text_component.mFontSize);
        }

        try self.mGlyphBufferBase.append(engine_context.FrameAllocator(), .{
            .Position = [3]f32{ pen_x, pen_y, world_pos[2] },
            .Rotation = [4]f32{ transform_component.Rotation[0], transform_component.Rotation[1], transform_component.Rotation[2], transform_component.Rotation[3] },
            .Scale = text_component.mFontSize,
            .AtlasBounds = [4]f32{ glyph_atlas_bounds[0], glyph_atlas_bounds[1], glyph_atlas_bounds[2], glyph_atlas_bounds[3] },
            .PlaneBounds = [4]f32{ glyph_plane_bounds[0], glyph_plane_bounds[1], glyph_plane_bounds[2], glyph_plane_bounds[3] },
            .AtlasIndex = atlas_asset.GetTextureHandle(),
            .TexIndex = texture_asset.GetTextureHandle(),
            .Color = [4]f32{ text_component.mTexOptions.mColor[0], text_component.mTexOptions.mColor[1], text_component.mTexOptions.mColor[2], text_component.mTexOptions.mColor[3] },
            .TexCoords = [4]f32{ text_component.mTexOptions.mTexCoords[0], text_component.mTexOptions.mTexCoords[1], text_component.mTexOptions.mTexCoords[2], text_component.mTexOptions.mTexCoords[3] },
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
