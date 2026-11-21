//! Where each glyph of a string goes. The one place that answers it, so the renderer drawing text,
//! picking testing against it and layout sizing it can never disagree.
//!
//! Generic over the font type so it builds without the engine: it only reads mGlyphs, mLineHeight,
//! mAscender, mDescender and ToArrayIndex (and mAtlasSize for GlyphUVs), which TextAsset has and a test font can fake.
const std = @import("std");
const MathTypes = @import("../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;

/// Decoding failures come out as this, which fonts map to their fallback (box) glyph.
const REPLACEMENT_CHAR: u21 = 0xFFFD;

pub const GlyphPlacement = struct {
    Pen: Vec2(f32), //baseline pen position, local to the text origin (the first line's baseline), x right y up
    PlaneCenter: Vec2(f32), //the glyph box's center relative to Pen, already scaled by the font size
    HalfExtents: Vec2(f32),
    //the glyph's place in its font (ToArrayIndex), the same for every use of the same letter. Where it is in the
    //font's atlas is GlyphUVs, which only the renderer needs, once per letter
    AtlasIndex: u32,
};

/// Where glyph `atlas_index` of `font` is in its atlas, normalized: bottom-left and top-right, since textures load
/// flipped so v runs bottom up (matching the font json's yOrigin bottom), and the glyph box's local UV runs bottom up too
pub fn GlyphUVs(comptime FontT: type, font: *const FontT, atlas_index: u32) struct { UV0: Vec2(f32), UV1: Vec2(f32) } {
    const glyph = &font.mGlyphs[atlas_index];
    //atlas texels are (left, top) and (right, bottom), so the corners' y swap
    return .{
        .UV0 = Vec2(f32).DivVec(.{ .x = glyph.mAtlasTexel0.x, .y = glyph.mAtlasTexel1.y }, font.mAtlasSize),
        .UV1 = Vec2(f32).DivVec(.{ .x = glyph.mAtlasTexel1.x, .y = glyph.mAtlasTexel0.y }, font.mAtlasSize),
    };
}

/// Logical bounds: from x = 0 to the widest line's advance, and from the first line's ascender down
/// to the last line's descender. They don't depend on which letters are in the text, so a line's
/// height doesn't jump around as it is typed, and a click between two letters still lands on it.
pub const Metrics = struct {
    Min: Vec2(f32),
    Max: Vec2(f32),
    LineCount: u32,

    /// How much room the text takes: the width of its widest line by the height of all its lines
    pub fn Size(self: Metrics) Vec2(f32) {
        return self.Max.SubVec(self.Min);
    }

    /// The middle of that room, relative to where the text is placed (its first line's baseline, where lines start)
    pub fn Center(self: Metrics) Vec2(f32) {
        return self.Min.AddVec(self.Max).MulScalar(0.5);
    }
};

pub fn Iterator(comptime FontT: type) type {
    return struct {
        const Self = @This();

        mText: []const u8,
        mFont: *const FontT,
        mFontSize: f32,
        mWrapWidth: f32, //0 or less never wraps
        mIndex: usize = 0, //byte index of the next codepoint
        mPen: Vec2(f32) = .{ .x = 0, .y = 0 },
        mLineCount: u32 = 1,
        mMaxLineWidth: f32 = 0,
        //the codepoint at byte mDecodedAt, decoded already by the kerning check of the glyph before it
        mDecoded: Decoded = undefined,
        mDecodedAt: usize = std.math.maxInt(usize),

        pub fn Init(text: []const u8, font: *const FontT, font_size: f32, wrap_width: f32) Self {
            return .{ .mText = text, .mFont = font, .mFontSize = font_size, .mWrapWidth = wrap_width };
        }

        /// The next glyph to draw. Codepoints with nothing to draw (spaces, newlines) only move the
        /// pen, so they never come out of here.
        pub fn Next(self: *Self) ?GlyphPlacement {
            while (self.mIndex < self.mText.len) {
                if (self.Step()) |placement| return placement;
            }
            return null;
        }

        /// Moves the pen past the one codepoint at mIndex, and returns where it is drawn if it has anything to draw.
        /// Only call it while mIndex is inside the text
        pub fn Step(self: *Self) ?GlyphPlacement {
            const decoded = if (self.mDecodedAt == self.mIndex) self.mDecoded else DecodeAt(self.mText, self.mIndex);
            self.mIndex += decoded.Len;

            if (decoded.Codepoint == '\n') {
                self.NewLine();
                return null;
            }

            const atlas_index = FontT.ToArrayIndex(decoded.Codepoint);
            const glyph = &self.mFont.mGlyphs[atlas_index];
            const advance = glyph.mAdvance * self.mFontSize;

            //a glyph without plane bounds has no ink (a space). it only advances, and never wraps
            //the line, so trailing spaces can't push a word onto a line of its own
            if (glyph.mPlaneMax.x <= glyph.mPlaneMin.x) {
                self.Advance(advance);
                return null;
            }

            //the pen > 0 check stops a glyph wider than the whole wrap width from leaving an empty line
            if (self.mWrapWidth > 0 and self.mPen.x > 0 and self.mPen.x + advance > self.mWrapWidth * (1 + WRAP_SLACK)) {
                self.NewLine();
            }

            //plane bounds are (left, top) and (right, bottom) at font size 1, y up
            const left = glyph.mPlaneMin.x;
            const top = glyph.mPlaneMin.y;
            const right = glyph.mPlaneMax.x;
            const bottom = glyph.mPlaneMax.y;

            const placement = GlyphPlacement{
                .Pen = self.mPen,
                .PlaneCenter = .{ .x = (left + right) * 0.5 * self.mFontSize, .y = (top + bottom) * 0.5 * self.mFontSize },
                .HalfExtents = .{ .x = (right - left) * 0.5 * self.mFontSize, .y = (top - bottom) * 0.5 * self.mFontSize },
                .AtlasIndex = @intCast(atlas_index),
            };

            self.Advance(advance + self.Kerning(glyph) * self.mFontSize);

            return placement;
        }

        /// Only complete once Next has returned null.
        pub fn GetMetrics(self: Self) Metrics {
            const last_baseline = -@as(f32, @floatFromInt(self.mLineCount - 1)) * self.mFont.mLineHeight * self.mFontSize;
            return .{
                .Min = .{ .x = 0, .y = last_baseline + self.mFont.mDescender * self.mFontSize },
                .Max = .{ .x = self.mMaxLineWidth, .y = self.mFont.mAscender * self.mFontSize },
                .LineCount = self.mLineCount,
            };
        }

        fn Advance(self: *Self, amount: f32) void {
            self.mPen.x += amount;
            self.mMaxLineWidth = @max(self.mMaxLineWidth, self.mPen.x);
        }

        fn NewLine(self: *Self) void {
            self.mPen.x = 0;
            self.mPen.y -= self.mFont.mLineHeight * self.mFontSize;
            self.mLineCount += 1;
        }

        /// The kerning between the glyph just placed and the codepoint after it, at font size 1. The next codepoint
        /// is only decoded for a glyph with kernings, and kept for the next Step
        fn Kerning(self: *Self, glyph: anytype) f32 {
            if (glyph.mKernings.count() == 0 or self.mIndex >= self.mText.len) return 0;
            self.mDecoded = DecodeAt(self.mText, self.mIndex);
            self.mDecodedAt = self.mIndex;
            const next_codepoint = self.mDecoded.Codepoint;
            //the font's kerning table is keyed by u16
            if (next_codepoint > std.math.maxInt(u16)) return 0;
            return glyph.mKernings.get(@intCast(next_codepoint)) orelse 0;
        }
    };
}

/// How far past its wrap width, as a share of it, a line can run and still fit. Layout wraps text at exactly the width
/// it measured, and the renderer measures it again with the font size and wrap width grown by the text's scale, which
/// rounds a little differently: without this the last letter could land a hair past the edge and drop onto a line of
/// its own, outside its box
const WRAP_SLACK: f32 = 1e-4;

/// Runs the same iterator the renderer draws with, so the size it reports is the size that gets drawn.
pub fn Measure(comptime FontT: type, text: []const u8, font: *const FontT, font_size: f32, wrap_width: f32) Metrics {
    var iter = Iterator(FontT).Init(text, font, font_size, wrap_width);
    while (iter.Next()) |_| {}
    return iter.GetMetrics();
}

/// How far any glyph of a font can go, at font size 1: the most one codepoint moves the pen (its advance and its
/// largest kerning), and the box every glyph's ink lies within around its pen (the pen itself included). Worked out
/// once for a font (TextAsset keeps it), so Reach can bound a text without laying it out
pub const FontReach = struct {
    Step: f32,
    InkMin: Vec2(f32),
    InkMax: Vec2(f32),

    pub fn Of(comptime FontT: type, font: *const FontT) FontReach {
        var reach = FontReach{ .Step = 0, .InkMin = .{ .x = 0, .y = 0 }, .InkMax = .{ .x = 0, .y = 0 } };
        for (&font.mGlyphs) |*glyph| {
            var kerning: f32 = 0;
            var kernings = glyph.mKernings.valueIterator();
            while (kernings.next()) |value| kerning = @max(kerning, value.*);
            reach.Step = @max(reach.Step, glyph.mAdvance + kerning);
            //no plane bounds, no ink (Iterator.Step)
            if (glyph.mPlaneMax.x <= glyph.mPlaneMin.x) continue;
            reach.InkMin.x = @min(reach.InkMin.x, glyph.mPlaneMin.x, glyph.mPlaneMax.x);
            reach.InkMin.y = @min(reach.InkMin.y, glyph.mPlaneMin.y, glyph.mPlaneMax.y);
            reach.InkMax.x = @max(reach.InkMax.x, glyph.mPlaneMin.x, glyph.mPlaneMax.x);
            reach.InkMax.y = @max(reach.InkMax.y, glyph.mPlaneMin.y, glyph.mPlaneMax.y);
        }
        return reach;
    }
};

/// A box in a text's layout space (GlyphPlacement.Pen's) that its layout can't reach past: every glyph's ink, and every
/// line from the first's ascender down to the last's descender (Metrics' height), across the widest any line can go.
/// Found without laying it out, from its bytes alone and `font_reach` (FontReach.Of its font): how many lines it can
/// have and how far along one the pen can be. Never smaller than the layout and often bigger, so a text it puts wholly
/// out of sight is out of sight whatever its layout
pub fn Reach(comptime FontT: type, text: []const u8, font: *const FontT, font_reach: FontReach, font_size: f32, wrap_width: f32) struct { Min: Vec2(f32), Max: Vec2(f32) } {
    //its lines between newlines, and the longest of them in bytes: a codepoint is at least one byte
    var newlines: usize = 0;
    var longest: usize = 0;
    var line: usize = 0;
    for (text) |byte| {
        if (byte == '\n') {
            newlines += 1;
            longest = @max(longest, line);
            line = 0;
        } else line += 1;
    }
    longest = @max(longest, line);

    //no glyph's pen is further along its line than every codepoint before it there moving it a whole step
    const step = font_reach.Step * font_size;
    var lines: f32 = @floatFromInt(1 + newlines);
    var pen_x: f32 = @as(f32, @floatFromInt(longest)) * step;
    if (wrap_width > 0) {
        //a glyph past the start of a line has to fit before its line's end, and a line only wraps once the pen has gone
        //further than that end less one step, which the whole text's steps can only pay for so many times
        const line_end = wrap_width * (1 + WRAP_SLACK);
        pen_x = @min(pen_x, line_end);
        const all_steps = @as(f32, @floatFromInt(text.len)) * step;
        lines += if (line_end > step) @ceil(all_steps / (line_end - step)) else @floatFromInt(text.len);
    }
    const last_baseline = -(lines - 1) * font.mLineHeight * font_size;

    var min = Vec2(f32){ .x = font_reach.InkMin.x * font_size, .y = last_baseline + @min(font_reach.InkMin.y, font.mDescender) * font_size };
    var max = Vec2(f32){ .x = pen_x + font_reach.InkMax.x * font_size, .y = @max(font_reach.InkMax.y, font.mAscender) * font_size };
    //a little room for the rounding of adding the steps up one at a time
    const size = max.SubVec(min);
    const pad = Vec2(f32){ .x = size.x * 1e-3 + 1e-4, .y = size.y * 1e-3 + 1e-4 };
    min = min.SubVec(pad);
    max = max.AddVec(pad);
    return .{ .Min = min, .Max = max };
}

/// Where a caret just before the byte at `index` sits: the pen once everything before it is laid out, local to the
/// text origin like GlyphPlacement.Pen, so on that line's baseline. `index` is the text's length for the end of it.
/// A caret before a word that wraps stays at the end of the line above, where the word was typed
pub fn CaretPen(comptime FontT: type, text: []const u8, font: *const FontT, font_size: f32, wrap_width: f32, index: usize) Vec2(f32) {
    var iter = Iterator(FontT).Init(text, font, font_size, wrap_width);
    while (iter.mIndex < @min(index, text.len)) _ = iter.Step();
    return iter.mPen;
}

/// The caret position nearest `point` (local to the text origin, like GlyphPlacement.Pen): the byte index of a
/// codepoint's start, or the text's length. The line the point is on comes first, then the nearest spot along it. A
/// point above the first line or below the last goes to that line
pub fn CaretIndexAt(comptime FontT: type, text: []const u8, font: *const FontT, font_size: f32, wrap_width: f32, point: Vec2(f32)) usize {
    const line_height = font.mLineHeight * font_size;
    const line_count = Measure(FontT, text, font, font_size, wrap_width).LineCount;
    //each line takes the room from its ascender down to the next line's
    const lines_down = if (line_height > 0) @floor((font.mAscender * font_size - point.y) / line_height) else 0;
    const line = std.math.clamp(lines_down, 0, @as(f32, @floatFromInt(line_count - 1)));
    const baseline = -line * line_height;

    var iter = Iterator(FontT).Init(text, font, font_size, wrap_width);
    var best_index: usize = 0;
    var best_distance = std.math.inf(f32);
    while (true) {
        //a caret before mIndex sits at the pen
        if (@abs(iter.mPen.y - baseline) <= line_height * 0.5) {
            const distance = @abs(iter.mPen.x - point.x);
            if (distance < best_distance) {
                best_distance = distance;
                best_index = iter.mIndex;
            }
        }
        if (iter.mIndex >= text.len) break;
        _ = iter.Step();
    }
    return best_index;
}

const Decoded = struct { Codepoint: u21, Len: usize };

/// One UTF-8 codepoint at `index`. Invalid or cut-off bytes decode to the replacement character one
/// byte at a time, so bad text draws boxes instead of crashing or swallowing what follows.
fn DecodeAt(text: []const u8, index: usize) Decoded {
    //plain ASCII is its own codepoint
    if (text[index] < 0x80) return .{ .Codepoint = text[index], .Len = 1 };
    const len = std.unicode.utf8ByteSequenceLength(text[index]) catch return .{ .Codepoint = REPLACEMENT_CHAR, .Len = 1 };
    if (index + len > text.len) return .{ .Codepoint = REPLACEMENT_CHAR, .Len = 1 };
    const codepoint = std.unicode.utf8Decode(text[index .. index + len]) catch return .{ .Codepoint = REPLACEMENT_CHAR, .Len = 1 };
    return .{ .Codepoint = codepoint, .Len = len };
}
