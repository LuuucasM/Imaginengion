const std = @import("std");
const SSBO = @import("../SSBOs/SSBO.zig");
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

const Tracy = @import("../Core/Tracy.zig");

const Renderer2D = @This();

const MAX_PATH_LEN = 256;

pub const QuadVertexPositions = Mat4f32{
    Vec4f32{ -0.5, -0.5, 0.0, 1.0 },
    Vec4f32{ 0.5, -0.5, 0.0, 1.0 },
    Vec4f32{ 0.5, 0.5, 0.0, 1.0 },
    Vec4f32{ -0.5, 0.5, 0.0, 1.0 },
};

pub const TextureOptions = extern struct {
    Color: [4]f32 = [4]f32{ 1.0, 1.0, 1.0, 1.0 },
    TexCoords: [4]f32 = [4]f32{ 0, 0, 1, 1 },
    TilingFactor: f32 = 1.0,
    _padding0: [3]f32 = [3]f32{ 0.0, 0.0, 0.0 }, // Pad to 16-byte boundary
};

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
    TexIndex: u64, // 8-byte aligned naturally here
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
    AtlasIndex: u64, // 8-byte aligned
    TexIndex: u64, // 8-byte aligned
};

const RectVertexPositions = Mat4f32{
    Vec4f32{ -0.5, -0.5, 0.0, 1.0 },
    Vec4f32{ 0.5, -0.5, 0.0, 1.0 },
    Vec4f32{ 0.5, 0.5, 0.0, 1.0 },
    Vec4f32{ -0.5, 0.5, 0.0, 1.0 },
};

mQuadBuffer: SSBO = undefined,
mQuadBufferBase: std.ArrayList(QuadData) = .{},
mQuadCountUB: UniformBuffer = undefined,

mGlyphBuffer: SSBO = undefined,
mGlyphBufferBase: std.ArrayList(GlyphData) = .{},
mGlyphCountUB: UniformBuffer = undefined,

pub fn Init(self: *Renderer2D, engine_allocator: std.mem.Allocator) !void {
    self.mQuadBuffer = SSBO.Init(@sizeOf(QuadData) * 100);
    self.mQuadBufferBase = try std.ArrayList(QuadData).initCapacity(engine_allocator, 100);
    self.mQuadCountUB = UniformBuffer.Init(@sizeOf(c_uint));

    self.mGlyphBuffer = SSBO.Init(@sizeOf(GlyphData) * 100);
    self.mGlyphBufferBase = try std.ArrayList(GlyphData).initCapacity(engine_allocator, 100);
    self.mGlyphCountUB = UniformBuffer.Init(@sizeOf(c_uint));
}

pub fn Deinit(self: *Renderer2D, engine_allocator: std.mem.Allocator) void {
    self.mQuadBuffer.Deinit();
    self.mQuadBufferBase.deinit(engine_allocator);
    self.mQuadCountUB.Deinit();

    self.mGlyphBuffer.Deinit();
    self.mGlyphBufferBase.deinit(engine_allocator);
    self.mGlyphCountUB.Deinit();
}

pub fn StartBatch(self: *Renderer2D, engine_allocator: std.mem.Allocator) void {
    self.mQuadBufferBase.clearAndFree(engine_allocator);
    self.mGlyphBufferBase.clearAndFree(engine_allocator);
}

pub fn SetBuffers(self: *Renderer2D) !void {
    const zone = Tracy.ZoneInit("R2D SetBuffers", @src());
    defer zone.Deinit();
    //quads
    if (self.mQuadBufferBase.items.len > 0) {
        self.mQuadBuffer.SetData(self.mQuadBufferBase.items.ptr, self.mQuadBufferBase.items.len * @sizeOf(QuadData), 0);
    }
    var quad_count: c_int = @intCast(self.mQuadBufferBase.items.len);
    self.mQuadCountUB.SetData(@ptrCast(&quad_count), @sizeOf(c_uint), 0);

    //glyphs
    if (self.mGlyphBufferBase.items.len > 0) {
        self.mGlyphBuffer.SetData(self.mGlyphBufferBase.items.ptr, self.mGlyphBufferBase.items.len * @sizeOf(GlyphData), 0);
    }
    var glyph_count: c_int = @intCast(self.mGlyphBufferBase.items.len);
    self.mGlyphCountUB.SetData(@ptrCast(&glyph_count), @sizeOf(c_uint), 0);

    //more shapes
}

pub fn BindBuffers(self: *Renderer2D) void {
    const zone = Tracy.ZoneInit("R2D BindBuffers", @src());
    defer zone.Deinit();

    //UBO
    //start at 2 cuz 0 is camera and 1 is rendering mode
    self.mQuadCountUB.Bind(2);
    self.mGlyphCountUB.Bind(3);

    //SSBO
    self.mQuadBuffer.Bind(0);
    self.mGlyphBuffer.Bind(1);
}

pub fn DrawQuad(self: *Renderer2D, engine_context: *EngineContext, transform_component: *EntityTransformComponent, quad_component: *QuadComponent) !void {
    const zone = Tracy.ZoneInit("R2D DrawQuad", @src());
    defer zone.Deinit();

    const texture_asset = try quad_component.mTexture.GetAsset(engine_context, Texture2D);

    const world_pos = transform_component.GetWorldPosition();
    const world_rot = transform_component.GetWorldRotation();
    const world_scale = transform_component.GetWorldScale();

    try self.mQuadBufferBase.append(engine_context.EngineAllocator(), .{
        .Position = [3]f32{ world_pos[0], world_pos[1], world_pos[2] },
        .Rotation = [4]f32{ world_rot[0], world_rot[1], world_rot[2], world_rot[3] },
        .Scale = [3]f32{ world_scale[0], world_scale[1], world_scale[2] },
        .TexIndex = texture_asset.GetBindlessID(),
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
            .AtlasIndex = atlas_asset.GetBindlessID(),
            .TexIndex = texture_asset.GetBindlessID(),
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
