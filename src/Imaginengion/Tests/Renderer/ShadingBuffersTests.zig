//! ShadingBuffers.GlyphSurface: one atlas entry per letter per font atlas, shared by every glyph of it in a render.
//! Run with `zig build test-engine`.
const std = @import("std");
const ShadingBuffers = @import("../../Renderer/Renderer.zig").ShadingBuffers;
const Vec2 = @import("../../Math/MathTypes.zig").Vec2;

const allocator = std.testing.allocator;

const UV0 = Vec2(f32){ .x = 0.25, .y = 0.5 };
const UV1 = Vec2(f32){ .x = 0.5, .y = 0.75 };

/// The atlas entry for `glyph` of the atlas in texture slot `atlas`
fn Entry(buffers: *ShadingBuffers, atlas: u32, glyph: u32) !usize {
    return buffers.GlyphSurface(allocator, .{ .AtlasTexture = atlas, .Glyph = glyph }, 512, 256, UV0, UV1);
}

fn Free(buffers: *ShadingBuffers) void {
    buffers.Reset(allocator, .ClearAndFree);
}

test "the same letter of the same atlas gets one entry, however many glyphs use it" {
    var buffers = ShadingBuffers{};
    defer Free(&buffers);
    const first = try Entry(&buffers, 3, 69);
    try std.testing.expectEqual(first, try Entry(&buffers, 3, 69));
    try std.testing.expectEqual(first, try Entry(&buffers, 3, 69));
    try std.testing.expectEqual(@as(usize, 1), buffers.mSurfShadingBuffBase.items.len);
}

test "a different letter, or the same letter in another font's atlas, gets its own entry" {
    var buffers = ShadingBuffers{};
    defer Free(&buffers);
    const e = try Entry(&buffers, 3, 69);
    const f = try Entry(&buffers, 3, 70);
    const other_font_e = try Entry(&buffers, 4, 69);
    try std.testing.expect(e != f and e != other_font_e and f != other_font_e);
    try std.testing.expectEqual(@as(usize, 3), buffers.mSurfShadingBuffBase.items.len);
}

test "an entry says where its letter is in its atlas, painted plain white" {
    var buffers = ShadingBuffers{};
    defer Free(&buffers);
    const entry = buffers.mSurfShadingBuffBase.items[try Entry(&buffers, 3, 69)];
    try std.testing.expectEqual(@as(u32, 3), entry.Texturehandle);
    try std.testing.expectEqual(@as(u32, 512), entry.TextureWidth);
    try std.testing.expectEqual(@as(u32, 256), entry.TextureHeight);
    try std.testing.expectEqualSlices(f32, &UV0.ToArray(), &entry.TextureUV0);
    try std.testing.expectEqualSlices(f32, &UV1.ToArray(), &entry.TextureUV1);
    try std.testing.expectEqualSlices(f32, &.{ 1, 1, 1, 1 }, &entry.Color);
}

test "a reset forgets the entries along with the shadings" {
    var buffers = ShadingBuffers{};
    defer Free(&buffers);
    _ = try Entry(&buffers, 3, 69);
    buffers.Reset(allocator, .ClearRetainingCapacity);
    try std.testing.expectEqual(@as(usize, 0), buffers.mGlyphSurfaces.count());
    //the next render adds it again, into the emptied shadings
    try std.testing.expectEqual(@as(usize, 0), try Entry(&buffers, 3, 69));
}
