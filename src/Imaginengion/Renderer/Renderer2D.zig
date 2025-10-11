const std = @import("std");
const SSBO = @import("../SSBOs/SSBO.zig");
const VertexArray = @import("../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const UniformBuffer = @import("../UniformBuffers/UniformBuffer.zig");
const ShaderAsset = @import("../Assets/Assets.zig").ShaderAsset;
const AssetHandle = @import("../Assets/AssetHandle.zig");
const AssetManager = @import("../Assets/AssetManager.zig");
const IndexBuffer = @import("../IndexBuffers/IndexBuffer.zig");

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
    Position: [3]f32,
    _padding0: f32 = 0.0,
    Rotation: [4]f32,
    Scale: [3]f32,
    _padding1: f32 = 0.0,
    TexOptions: TextureOptions = .{},
    TexIndex: u64, // 8-byte aligned naturally here
};

pub const GlyphData = extern struct {
    Position: [3]f32,
    Scale: f32, // Moved here to fill the vec3 padding
    Rotation: [4]f32,
    AtlasBounds: [4]f32,
    PlaneBounds: [4]f32,
    TextureOptions: TextureOptions,
    AtlasIndex: u64, // 8-byte aligned
    TexIndex: u64, // 8-byte aligned
};

const RectVertexPositions = Mat4f32{
    Vec4f32{ -0.5, -0.5, 0.0, 1.0 },
    Vec4f32{ 0.5, -0.5, 0.0, 1.0 },
    Vec4f32{ 0.5, 0.5, 0.0, 1.0 },
    Vec4f32{ -0.5, 0.5, 0.0, 1.0 },
};

mAllocator: std.mem.Allocator,

mQuadBuffer: SSBO,
mQuadBufferBase: std.ArrayList(QuadData) = .{},
mQuadCountUB: UniformBuffer,

mGlyphBuffer: SSBO,
mGlyphBufferBase: std.ArrayList(GlyphData) = .{},
mGlyphCountUB: UniformBuffer,

_Allocator: std.mem.Allocator,

pub fn Init(allocator: std.mem.Allocator) !Renderer2D {
    return Renderer2D{
        .mAllocator = allocator,

        .mQuadBuffer = SSBO.Init(@sizeOf(QuadData) * 100),
        .mQuadBufferBase = try std.ArrayList(QuadData).initCapacity(allocator, 100),
        .mQuadCountUB = UniformBuffer.Init(@sizeOf(c_uint)),

        .mGlyphBuffer = SSBO.Init(@sizeOf(GlyphData) * 100),
        .mGlyphBufferBase = try std.ArrayList(GlyphData).initCapacity(allocator, 100),
        .mGlyphCountUB = UniformBuffer.Init(@sizeOf(c_uint)),

        ._Allocator = allocator,
    };
}

pub fn Deinit(self: *Renderer2D) !void {
    self.mQuadBuffer.Deinit();
    self.mQuadBufferBase.deinit(self._Allocator);
    self.mQuadCountUB.Deinit();

    self.mGlyphBuffer.Deinit();
    self.mGlyphBufferBase.deinit(self._Allocator);
    self.mGlyphCountUB.Deinit();
}

pub fn StartBatch(self: *Renderer2D) void {
    self.mQuadBufferBase.clearAndFree(self._Allocator);
    self.mGlyphBufferBase.clearAndFree(self._Allocator);
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

pub fn DrawQuad(self: *Renderer2D, transform_component: *EntityTransformComponent, quad_component: *QuadComponent) !void {
    const zone = Tracy.ZoneInit("R2D DrawQuad", @src());
    defer zone.Deinit();

    const texture_asset = try quad_component.mTexture.GetAsset(Texture2D);

    try self.mQuadBufferBase.append(self._Allocator, .{
        .Position = [3]f32{ transform_component.Translation[0], transform_component.Translation[1], transform_component.Translation[2] },
        .Rotation = [4]f32{ transform_component.Rotation[0], transform_component.Rotation[1], transform_component.Rotation[2], transform_component.Rotation[3] },
        .Scale = [3]f32{ transform_component.Scale[0], transform_component.Scale[1], transform_component.Scale[2] },
        .TexOptions = TextureOptions{
            .Color = [4]f32{ quad_component.mTexOptions.mColor[0], quad_component.mTexOptions.mColor[1], quad_component.mTexOptions.mColor[2], quad_component.mTexOptions.mColor[3] },
            .TexCoords = [4]f32{ quad_component.mTexOptions.mTexCoords[0], quad_component.mTexOptions.mTexCoords[1], quad_component.mTexOptions.mTexCoords[2], quad_component.mTexOptions.mTexCoords[3] },
            .TilingFactor = quad_component.mTexOptions.mTilingFactor,
        },
        .TexIndex = texture_asset.GetBindlessID(),
    });
}

pub fn DrawText(self: *Renderer2D, transform_component: *EntityTransformComponent, text_component: *TextComponent) !void {
    const zone = Tracy.ZoneInit("R2D DrawQuad", @src());
    defer zone.Deinit();

    const text_asset = try text_component.mTextAssetHandle.GetAsset(TextAsset);
    const atlas_asset = try text_component.mAtlasHandle.GetAsset(Texture2D);
    const texture_asset = try text_component.mTexHandle.GetAsset(Texture2D);

    const left_bounds = transform_component.Translation[0] - text_component.mBounds[0];
    const right_bounds = transform_component.Translation[0] + text_component.mBounds[1];

    var pen_x = left_bounds;
    var pen_y = transform_component.Translation[1];

    for (text_component.mText.items, 0..) |char, i| {
        const array_ind = TextAsset.ToArrayIndex(char);
        const glyph = text_asset.mGlyphs[array_ind];

        if (char == 32) { //if its space just continue on
            pen_x += glyph.mAdvance;
            continue;
        }

        const glyph_atlas_bounds = glyph.mAtlasBounds;
        const glyph_plane_bounds = glyph.mPlaneBounds;

        const glyph_width = glyph.mAdvance;

        if (pen_x + glyph_width > right_bounds) {
            pen_x = left_bounds;
            pen_y -= text_asset.mLineHeight;
        }

        try self.mGlyphBufferBase.append(self._Allocator, .{
            .Position = [3]f32{ pen_x, pen_y, transform_component.Translation[2] },
            .Rotation = [4]f32{ transform_component.Rotation[0], transform_component.Rotation[1], transform_component.Rotation[2], transform_component.Rotation[3] },
            .Scale = text_component.mFontSize,
            .TextureOptions = TextureOptions{
                .Color = [4]f32{ text_component.mTexOptions.mColor[0], text_component.mTexOptions.mColor[1], text_component.mTexOptions.mColor[2], text_component.mTexOptions.mColor[3] },
                .TexCoords = [4]f32{ text_component.mTexOptions.mTexCoords[0], text_component.mTexOptions.mTexCoords[1], text_component.mTexOptions.mTexCoords[2], text_component.mTexOptions.mTexCoords[3] },
                .TilingFactor = text_component.mTexOptions.mTilingFactor,
            },
            .AtlasBounds = [4]f32{ glyph_atlas_bounds[0], glyph_atlas_bounds[1], glyph_atlas_bounds[2], glyph_atlas_bounds[3] },
            .PlaneBounds = [4]f32{ glyph_plane_bounds[0], glyph_plane_bounds[1], glyph_plane_bounds[2], glyph_plane_bounds[3] },
            .AtlasIndex = atlas_asset.GetBindlessID(),
            .TexIndex = texture_asset.GetBindlessID(),
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
