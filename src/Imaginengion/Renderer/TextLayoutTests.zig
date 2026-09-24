const std = @import("std");
const MathTypes = @import("../Math/MathTypes.zig");
const TextLayout = @import("TextLayout.zig");
const Vec2 = MathTypes.Vec2;

const eps: f32 = 0.0001;

//a stand in for TextAsset with just the fields TextLayout reads, so these tests build without the engine
const KerningsT = std.AutoHashMap(u16, f32);

const FakeGlyph = struct {
    mAtlasTexel0: Vec2(f32) = .{ .x = -1, .y = -1 },
    mAtlasTexel1: Vec2(f32) = .{ .x = -1, .y = -1 },
    mPlaneMin: Vec2(f32) = .{ .x = -1, .y = -1 }, //left, top
    mPlaneMax: Vec2(f32) = .{ .x = -1, .y = -1 }, //right, bottom
    mAdvance: f32 = -1,
    mKernings: KerningsT,
};

const A_IND = 0;
const V_IND = 1;
const SPACE_IND = 2;
const HANGUL_IND = 3;
const BOX_IND = 4;

const LINE_HEIGHT: f32 = 1.2;
const ASCENDER: f32 = 0.9;
const DESCENDER: f32 = -0.2;
const A_V_KERNING: f32 = -0.1;

const FakeFont = struct {
    mGlyphs: [5]FakeGlyph,
    mLineHeight: f32 = LINE_HEIGHT,
    mAscender: f32 = ASCENDER,
    mDescender: f32 = DESCENDER,
    mAtlasSize: Vec2(f32) = .{ .x = 100, .y = 100 },

    pub fn ToArrayIndex(unicode: usize) usize {
        return switch (unicode) {
            'A' => A_IND,
            'V' => V_IND,
            ' ' => SPACE_IND,
            0xAC00 => HANGUL_IND, //가
            else => BOX_IND,
        };
    }

    fn Init(allocator: std.mem.Allocator) !FakeFont {
        var font = FakeFont{ .mGlyphs = undefined };
        font.mGlyphs[A_IND] = .{
            //(left, top) and (right, bottom) in a bottom-origin atlas, like the real font json
            .mAtlasTexel0 = .{ .x = 10, .y = 50 },
            .mAtlasTexel1 = .{ .x = 30, .y = 20 },
            .mPlaneMin = .{ .x = 0, .y = 0.7 },
            .mPlaneMax = .{ .x = 0.5, .y = 0 },
            .mAdvance = 0.5,
            .mKernings = KerningsT.init(allocator),
        };
        try font.mGlyphs[A_IND].mKernings.put('V', A_V_KERNING);
        font.mGlyphs[V_IND] = .{ .mPlaneMin = .{ .x = 0, .y = 0.7 }, .mPlaneMax = .{ .x = 0.5, .y = 0 }, .mAdvance = 0.5, .mKernings = KerningsT.init(allocator) };
        //no plane bounds, like a space in the real font json
        font.mGlyphs[SPACE_IND] = .{ .mAdvance = 0.25, .mKernings = KerningsT.init(allocator) };
        font.mGlyphs[HANGUL_IND] = .{ .mPlaneMin = .{ .x = 0, .y = 0.8 }, .mPlaneMax = .{ .x = 1, .y = -0.1 }, .mAdvance = 1, .mKernings = KerningsT.init(allocator) };
        font.mGlyphs[BOX_IND] = .{ .mPlaneMin = .{ .x = 0, .y = 0.6 }, .mPlaneMax = .{ .x = 0.6, .y = 0 }, .mAdvance = 0.6, .mKernings = KerningsT.init(allocator) };
        return font;
    }

    fn Deinit(self: *FakeFont) void {
        for (&self.mGlyphs) |*glyph| glyph.mKernings.deinit();
    }
};

const Layout = TextLayout.Iterator(FakeFont);

/// Every glyph the iterator places, plus the final metrics.
fn Collect(text: []const u8, font: *const FakeFont, font_size: f32, wrap_width: f32) !struct { Glyphs: std.ArrayList(TextLayout.GlyphPlacement), Metrics: TextLayout.Metrics } {
    var glyphs: std.ArrayList(TextLayout.GlyphPlacement) = .empty;
    var iter = Layout.Init(text, font, font_size, wrap_width);
    while (iter.Next()) |glyph| try glyphs.append(std.testing.allocator, glyph);
    return .{ .Glyphs = glyphs, .Metrics = iter.GetMetrics() };
}

fn ExpectVec2(expected: Vec2(f32), actual: Vec2(f32)) !void {
    try std.testing.expectApproxEqAbs(expected.x, actual.x, eps);
    try std.testing.expectApproxEqAbs(expected.y, actual.y, eps);
}

test "a single glyph at size 1" {
    var font = try FakeFont.Init(std.testing.allocator);
    defer font.Deinit();
    var result = try Collect("A", &font, 1, 0);
    defer result.Glyphs.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), result.Glyphs.items.len);
    const glyph = result.Glyphs.items[0];
    try ExpectVec2(.{ .x = 0, .y = 0 }, glyph.Pen);
    try ExpectVec2(.{ .x = 0.25, .y = 0.35 }, glyph.PlaneCenter);
    try ExpectVec2(.{ .x = 0.25, .y = 0.35 }, glyph.HalfExtents);
    //bottom-left and top-right, so the glyph box's bottom-up local UV lerps straight across them
    try ExpectVec2(.{ .x = 0.1, .y = 0.2 }, glyph.UV0);
    try ExpectVec2(.{ .x = 0.3, .y = 0.5 }, glyph.UV1);

    try std.testing.expectApproxEqAbs(@as(f32, 0.5), result.Metrics.Max.x, eps);
    try std.testing.expectEqual(@as(u32, 1), result.Metrics.LineCount);
}

test "font size scales every position and size" {
    var font = try FakeFont.Init(std.testing.allocator);
    defer font.Deinit();
    var result = try Collect("AA", &font, 9, 0);
    defer result.Glyphs.deinit(std.testing.allocator);

    try ExpectVec2(.{ .x = 2.25, .y = 3.15 }, result.Glyphs.items[0].PlaneCenter);
    try ExpectVec2(.{ .x = 2.25, .y = 3.15 }, result.Glyphs.items[0].HalfExtents);
    try ExpectVec2(.{ .x = 4.5, .y = 0 }, result.Glyphs.items[1].Pen);
    try std.testing.expectApproxEqAbs(@as(f32, 9), result.Metrics.Max.x, eps);
    try std.testing.expectApproxEqAbs(ASCENDER * 9, result.Metrics.Max.y, eps);
    try std.testing.expectApproxEqAbs(DESCENDER * 9, result.Metrics.Min.y, eps);
}

test "kerning pulls the next glyph by the pair's value" {
    var font = try FakeFont.Init(std.testing.allocator);
    defer font.Deinit();

    var kerned = try Collect("AV", &font, 2, 0);
    defer kerned.Glyphs.deinit(std.testing.allocator);
    try std.testing.expectApproxEqAbs((0.5 + A_V_KERNING) * 2, kerned.Glyphs.items[1].Pen.x, eps);

    //the table is per ordered pair, V has none for A
    var unkerned = try Collect("VA", &font, 2, 0);
    defer unkerned.Glyphs.deinit(std.testing.allocator);
    try std.testing.expectApproxEqAbs(@as(f32, 1), unkerned.Glyphs.items[1].Pen.x, eps);
}

test "wrapping checks the scaled glyph width" {
    var font = try FakeFont.Init(std.testing.allocator);
    defer font.Deinit();
    //bounds (5, 5) is a wrap width of 10. each A is 4.5 wide at size 9, so two fit and the third wraps.
    //checking the unscaled advance instead (9 + 0.5 > 10 is false) would have put it at x = 9, poking past the bound
    var result = try Collect("AAA", &font, 9, 10);
    defer result.Glyphs.deinit(std.testing.allocator);

    try ExpectVec2(.{ .x = 4.5, .y = 0 }, result.Glyphs.items[1].Pen);
    try ExpectVec2(.{ .x = 0, .y = -LINE_HEIGHT * 9 }, result.Glyphs.items[2].Pen);
    try std.testing.expectEqual(@as(u32, 2), result.Metrics.LineCount);
    try std.testing.expectApproxEqAbs(-LINE_HEIGHT * 9 + DESCENDER * 9, result.Metrics.Min.y, eps);
}

test "a glyph wider than the wrap width does not leave an empty line" {
    var font = try FakeFont.Init(std.testing.allocator);
    defer font.Deinit();
    var result = try Collect("AA", &font, 1, 0.3);
    defer result.Glyphs.deinit(std.testing.allocator);

    try ExpectVec2(.{ .x = 0, .y = 0 }, result.Glyphs.items[0].Pen);
    try ExpectVec2(.{ .x = 0, .y = -LINE_HEIGHT }, result.Glyphs.items[1].Pen);
    try std.testing.expectEqual(@as(u32, 2), result.Metrics.LineCount);
}

test "newline starts a new line and draws nothing" {
    var font = try FakeFont.Init(std.testing.allocator);
    defer font.Deinit();
    var result = try Collect("A\nA", &font, 1, 0);
    defer result.Glyphs.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), result.Glyphs.items.len);
    try ExpectVec2(.{ .x = 0, .y = -LINE_HEIGHT }, result.Glyphs.items[1].Pen);
    try std.testing.expectEqual(@as(u32, 2), result.Metrics.LineCount);
}

test "spaces advance without drawing and never wrap" {
    var font = try FakeFont.Init(std.testing.allocator);
    defer font.Deinit();

    var spaced = try Collect("A A", &font, 1, 0);
    defer spaced.Glyphs.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), spaced.Glyphs.items.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), spaced.Glyphs.items[1].Pen.x, eps);

    //the space runs to 0.75, past nothing; the second A (0.75 + 0.5 > 0.8) is what wraps
    var wrapped = try Collect("A A", &font, 1, 0.8);
    defer wrapped.Glyphs.deinit(std.testing.allocator);
    try ExpectVec2(.{ .x = 0, .y = -LINE_HEIGHT }, wrapped.Glyphs.items[1].Pen);
    try std.testing.expectEqual(@as(u32, 2), wrapped.Metrics.LineCount);
}

test "a multi byte UTF-8 character is one glyph" {
    var font = try FakeFont.Init(std.testing.allocator);
    defer font.Deinit();
    //가 is 3 bytes in UTF-8, reading bytes would have drawn 3 boxes
    var result = try Collect("가A", &font, 1, 0);
    defer result.Glyphs.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), result.Glyphs.items.len);
    try ExpectVec2(.{ .x = 0.5, .y = 0.45 }, result.Glyphs.items[0].HalfExtents);
    try std.testing.expectApproxEqAbs(@as(f32, 1), result.Glyphs.items[1].Pen.x, eps);
}

test "invalid UTF-8 draws boxes instead of failing" {
    var font = try FakeFont.Init(std.testing.allocator);
    defer font.Deinit();
    //a lone continuation byte, then the first two bytes of a three byte character cut off at the end
    var result = try Collect("\x80A\xEA\xB0", &font, 1, 0);
    defer result.Glyphs.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), result.Glyphs.items.len);
    try ExpectVec2(.{ .x = 0.3, .y = 0.3 }, result.Glyphs.items[0].HalfExtents); //box
    try ExpectVec2(.{ .x = 0.25, .y = 0.35 }, result.Glyphs.items[1].HalfExtents); //A
    try ExpectVec2(.{ .x = 0.3, .y = 0.3 }, result.Glyphs.items[3].HalfExtents); //box
}

test "a codepoint past the kerning table's range is just unkerned" {
    var font = try FakeFont.Init(std.testing.allocator);
    defer font.Deinit();
    //U+1F600 doesn't fit the u16 keys, looking it up must not overflow
    var result = try Collect("A\u{1F600}", &font, 1, 0);
    defer result.Glyphs.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), result.Glyphs.items.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), result.Glyphs.items[1].Pen.x, eps);
}

test "empty text is one line tall and zero wide" {
    var font = try FakeFont.Init(std.testing.allocator);
    defer font.Deinit();
    const metrics = TextLayout.Measure(FakeFont, "", &font, 2, 0);

    try std.testing.expectEqual(@as(u32, 1), metrics.LineCount);
    try ExpectVec2(.{ .x = 0, .y = DESCENDER * 2 }, metrics.Min);
    try ExpectVec2(.{ .x = 0, .y = ASCENDER * 2 }, metrics.Max);
}

test "Measure matches what the iterator lays out" {
    var font = try FakeFont.Init(std.testing.allocator);
    defer font.Deinit();
    const text = "AV A\nAAAA 가";
    var result = try Collect(text, &font, 3, 5);
    defer result.Glyphs.deinit(std.testing.allocator);
    const measured = TextLayout.Measure(FakeFont, text, &font, 3, 5);

    try std.testing.expectEqual(result.Metrics.LineCount, measured.LineCount);
    try ExpectVec2(result.Metrics.Min, measured.Min);
    try ExpectVec2(result.Metrics.Max, measured.Max);

    //every glyph's pen sits inside the measured box
    for (result.Glyphs.items) |glyph| {
        try std.testing.expect(glyph.Pen.x >= 0 and glyph.Pen.x <= measured.Max.x);
        try std.testing.expect(glyph.Pen.y >= measured.Min.y and glyph.Pen.y <= measured.Max.y);
    }
}
