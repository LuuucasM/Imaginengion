const std = @import("std");
const MathTypes = @import("../../Math/MathTypes.zig");
const TextLayout = @import("../../Renderer/TextLayout.zig");
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
    const uvs = TextLayout.GlyphUVs(FakeFont, &font, glyph.AtlasIndex);
    try ExpectVec2(.{ .x = 0.1, .y = 0.2 }, uvs.UV0);
    try ExpectVec2(.{ .x = 0.3, .y = 0.5 }, uvs.UV1);

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

test "the metrics give the text's room and its middle, for layout to fit and center it" {
    var font = try FakeFont.Init(std.testing.allocator);
    defer font.Deinit();
    //two lines at font size 2: the widest is "AA", 2 wide; ascender down to the second line's descender
    const metrics = TextLayout.Measure(FakeFont, "AA\nA", &font, 2, 0);

    const top = ASCENDER * 2;
    const bottom = -LINE_HEIGHT * 2 + DESCENDER * 2;
    try ExpectVec2(.{ .x = 2, .y = top - bottom }, metrics.Size());
    try ExpectVec2(.{ .x = 1, .y = (top + bottom) / 2 }, metrics.Center());
}

test "a caret sits at the pen once everything before it is laid out, kerning and all" {
    var font = try FakeFont.Init(std.testing.allocator);
    defer font.Deinit();
    //at size 2: A is 1 wide but kerns 0.2 into V, V is 1 wide and has no kerning with A
    try ExpectVec2(.{ .x = 0, .y = 0 }, TextLayout.CaretPen(FakeFont, "AVA", &font, 2, 0, 0));
    try ExpectVec2(.{ .x = 0.8, .y = 0 }, TextLayout.CaretPen(FakeFont, "AVA", &font, 2, 0, 1));
    try ExpectVec2(.{ .x = 1.8, .y = 0 }, TextLayout.CaretPen(FakeFont, "AVA", &font, 2, 0, 2));
    try ExpectVec2(.{ .x = 2.8, .y = 0 }, TextLayout.CaretPen(FakeFont, "AVA", &font, 2, 0, 3));

    //after a line break: the start of the next line
    try ExpectVec2(.{ .x = 0, .y = -LINE_HEIGHT * 2 }, TextLayout.CaretPen(FakeFont, "A\nA", &font, 2, 0, 2));
    try ExpectVec2(.{ .x = 1, .y = -LINE_HEIGHT * 2 }, TextLayout.CaretPen(FakeFont, "A\nA", &font, 2, 0, 3));
}

test "a point lands the caret on the nearest spot of the line it is on" {
    var font = try FakeFont.Init(std.testing.allocator);
    defer font.Deinit();
    //caret spots at x 0, 0.8, 1.8 and 2.8
    try std.testing.expectEqual(@as(usize, 1), TextLayout.CaretIndexAt(FakeFont, "AVA", &font, 2, 0, .{ .x = 1.0, .y = 0.5 }));
    try std.testing.expectEqual(@as(usize, 2), TextLayout.CaretIndexAt(FakeFont, "AVA", &font, 2, 0, .{ .x = 1.4, .y = 0.5 }));
    try std.testing.expectEqual(@as(usize, 0), TextLayout.CaretIndexAt(FakeFont, "AVA", &font, 2, 0, .{ .x = -5, .y = 0.5 }));
    try std.testing.expectEqual(@as(usize, 3), TextLayout.CaretIndexAt(FakeFont, "AVA", &font, 2, 0, .{ .x = 100, .y = 0.5 }));
    try std.testing.expectEqual(@as(usize, 0), TextLayout.CaretIndexAt(FakeFont, "", &font, 2, 0, .{ .x = 3, .y = 0 }));

    //the second line, then above the first and below the last
    try std.testing.expectEqual(@as(usize, 3), TextLayout.CaretIndexAt(FakeFont, "A\nA", &font, 2, 0, .{ .x = 0.9, .y = -2 }));
    try std.testing.expectEqual(@as(usize, 1), TextLayout.CaretIndexAt(FakeFont, "A\nA", &font, 2, 0, .{ .x = 0.9, .y = 10 }));
    try std.testing.expectEqual(@as(usize, 2), TextLayout.CaretIndexAt(FakeFont, "A\nA", &font, 2, 0, .{ .x = -1, .y = -100 }));
}

test "text wrapped at exactly its own measured width stays on one line at any scale" {
    var font = try FakeFont.Init(std.testing.allocator);
    defer font.Deinit();
    //what layout does: measures the text unwrapped and gives it that width to wrap at. The renderer then lays it out
    //again with the font size and the wrap width both grown by the text's scale, which rounds differently
    const text = "AVAVA AVAVAVA VA";
    const width = TextLayout.Measure(FakeFont, text, &font, 1, 0).Size().x;
    var scale: f32 = 0.05;
    while (scale < 3) : (scale += 0.0137) {
        const metrics = TextLayout.Measure(FakeFont, text, &font, scale, width * scale);
        try std.testing.expectEqual(@as(u32, 1), metrics.LineCount);
    }
}

/// The iterator's answer key: each codepoint decoded on its own by std, then the same rules spelled out plainly
const Reference = struct {
    const Placed = struct { Pen: Vec2(f32), AtlasIndex: u32 };

    fn Decode(text: []const u8, index: usize) struct { Codepoint: u21, Len: usize } {
        const len = std.unicode.utf8ByteSequenceLength(text[index]) catch return .{ .Codepoint = 0xFFFD, .Len = 1 };
        if (index + len > text.len) return .{ .Codepoint = 0xFFFD, .Len = 1 };
        const codepoint = std.unicode.utf8Decode(text[index .. index + len]) catch return .{ .Codepoint = 0xFFFD, .Len = 1 };
        return .{ .Codepoint = codepoint, .Len = len };
    }

    fn Layout(out: *std.ArrayList(Placed), text: []const u8, font: *const FakeFont, size: f32, wrap: f32) !u32 {
        var pen = Vec2(f32){ .x = 0, .y = 0 };
        var lines: u32 = 1;
        var index: usize = 0;
        while (index < text.len) {
            const decoded = Decode(text, index);
            index += decoded.Len;
            if (decoded.Codepoint == '\n') {
                pen = .{ .x = 0, .y = pen.y - font.mLineHeight * size };
                lines += 1;
                continue;
            }
            const atlas_index = FakeFont.ToArrayIndex(decoded.Codepoint);
            const glyph = &font.mGlyphs[atlas_index];
            const advance = glyph.mAdvance * size;
            if (glyph.mPlaneMax.x <= glyph.mPlaneMin.x) {
                pen.x += advance;
                continue;
            }
            if (wrap > 0 and pen.x > 0 and pen.x + advance > wrap * (1 + 1e-4)) {
                pen = .{ .x = 0, .y = pen.y - font.mLineHeight * size };
                lines += 1;
            }
            try out.append(std.testing.allocator, .{ .Pen = pen, .AtlasIndex = @intCast(atlas_index) });
            var kerning: f32 = 0;
            if (index < text.len) {
                const next = Decode(text, index).Codepoint;
                if (next <= std.math.maxInt(u16)) kerning = glyph.mKernings.get(@intCast(next)) orelse 0;
            }
            pen.x += advance + kerning * size;
        }
        return lines;
    }
};

test "the iterator puts every letter where decoding each codepoint on its own says, kerning, wrapping and bad bytes too" {
    var font = try FakeFont.Init(std.testing.allocator);
    defer font.Deinit();
    //kernings on two letters, the rest none, so both the kerned and unkerned steps are taken
    try font.mGlyphs[V_IND].mKernings.put('A', 0.3);
    try font.mGlyphs[HANGUL_IND].mKernings.put('V', -0.2);

    var prng = std.Random.DefaultPrng.init(0x1E77);
    const random = prng.random();
    const pieces = [_][]const u8{ "A", "V", "A", "V", " ", "\n", "\xEA\xB0\x80", "\xFF", "\xE0", "\x80", "\xEA\xB0", "x" };
    var buffer: [200]u8 = undefined;
    var expected: std.ArrayList(Reference.Placed) = .empty;
    defer expected.deinit(std.testing.allocator);
    for (0..2000) |_| {
        var len: usize = 0;
        for (0..random.uintLessThan(usize, 50)) |_| {
            const piece = pieces[random.uintLessThan(usize, pieces.len)];
            if (len + piece.len > buffer.len) break;
            @memcpy(buffer[len..][0..piece.len], piece);
            len += piece.len;
        }
        const text = buffer[0..len];
        const sizes = [_]f32{ 1, 2.5, 9 };
        const wraps = [_]f32{ 0, 0.6, 2, 7 };
        const size = sizes[random.uintLessThan(usize, sizes.len)];
        const wrap = wraps[random.uintLessThan(usize, wraps.len)] * size;

        expected.clearRetainingCapacity();
        const lines = try Reference.Layout(&expected, text, &font, size, wrap);
        var iter = Layout.Init(text, &font, size, wrap);
        var count: usize = 0;
        while (iter.Next()) |glyph| : (count += 1) {
            try std.testing.expect(count < expected.items.len);
            try std.testing.expectEqual(expected.items[count].AtlasIndex, glyph.AtlasIndex);
            try std.testing.expectEqual(expected.items[count].Pen, glyph.Pen);
        }
        try std.testing.expectEqual(expected.items.len, count);
        try std.testing.expectEqual(lines, iter.GetMetrics().LineCount);
    }
}
