//! Where each glyph of a string goes. The one place that answers it, so the renderer drawing text,
//! picking testing against it and layout sizing it can never disagree.
//!
//! Generic over the font type so it builds without the engine: it only reads mGlyphs, mLineHeight,
//! mAscender, mDescender, mAtlasSize and ToArrayIndex, which TextAsset has and a test font can fake.
const std = @import("std");
const MathTypes = @import("../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;

/// Decoding failures come out as this, which fonts map to their fallback (box) glyph.
const REPLACEMENT_CHAR: u21 = 0xFFFD;

pub const GlyphPlacement = struct {
    Pen: Vec2(f32), //baseline pen position, local to the text origin (the first line's baseline), x right y up
    PlaneCenter: Vec2(f32), //the glyph box's center relative to Pen, already scaled by the font size
    HalfExtents: Vec2(f32),
    //atlas UVs, normalized. bottom-left and top-right, since textures load flipped so v runs bottom
    //up (matching the font json's yOrigin bottom), and the glyph box's local UV runs bottom up too
    UV0: Vec2(f32),
    UV1: Vec2(f32),
};

/// Logical bounds: from x = 0 to the widest line's advance, and from the first line's ascender down
/// to the last line's descender. They don't depend on which letters are in the text, so a line's
/// height doesn't jump around as it is typed, and a click between two letters still lands on it.
pub const Metrics = struct {
    Min: Vec2(f32),
    Max: Vec2(f32),
    LineCount: u32,
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

        pub fn Init(text: []const u8, font: *const FontT, font_size: f32, wrap_width: f32) Self {
            return .{ .mText = text, .mFont = font, .mFontSize = font_size, .mWrapWidth = wrap_width };
        }

        /// The next glyph to draw. Codepoints with nothing to draw (spaces, newlines) only move the
        /// pen, so they never come out of here.
        pub fn Next(self: *Self) ?GlyphPlacement {
            while (self.mIndex < self.mText.len) {
                const decoded = DecodeAt(self.mText, self.mIndex);
                self.mIndex += decoded.Len;

                if (decoded.Codepoint == '\n') {
                    self.NewLine();
                    continue;
                }

                const glyph = &self.mFont.mGlyphs[FontT.ToArrayIndex(decoded.Codepoint)];
                const advance = glyph.mAdvance * self.mFontSize;

                //a glyph without plane bounds has no ink (a space). it only advances, and never wraps
                //the line, so trailing spaces can't push a word onto a line of its own
                if (glyph.mPlaneMax.x <= glyph.mPlaneMin.x) {
                    self.Advance(advance);
                    continue;
                }

                //the pen > 0 check stops a glyph wider than the whole wrap width from leaving an empty line
                if (self.mWrapWidth > 0 and self.mPen.x > 0 and self.mPen.x + advance > self.mWrapWidth) {
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
                    //atlas texels are (left, top) and (right, bottom), so the corners' y swap
                    .UV0 = Vec2(f32).DivVec(.{ .x = glyph.mAtlasTexel0.x, .y = glyph.mAtlasTexel1.y }, self.mFont.mAtlasSize),
                    .UV1 = Vec2(f32).DivVec(.{ .x = glyph.mAtlasTexel1.x, .y = glyph.mAtlasTexel0.y }, self.mFont.mAtlasSize),
                };

                self.Advance(advance + self.Kerning(glyph) * self.mFontSize);

                return placement;
            }
            return null;
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

        /// The kerning between the glyph just placed and the codepoint after it, at font size 1.
        fn Kerning(self: Self, glyph: anytype) f32 {
            if (self.mIndex >= self.mText.len) return 0;
            const next_codepoint = DecodeAt(self.mText, self.mIndex).Codepoint;
            //the font's kerning table is keyed by u16
            if (next_codepoint > std.math.maxInt(u16)) return 0;
            return glyph.mKernings.get(@intCast(next_codepoint)) orelse 0;
        }
    };
}

/// Runs the same iterator the renderer draws with, so the size it reports is the size that gets drawn.
pub fn Measure(comptime FontT: type, text: []const u8, font: *const FontT, font_size: f32, wrap_width: f32) Metrics {
    var iter = Iterator(FontT).Init(text, font, font_size, wrap_width);
    while (iter.Next()) |_| {}
    return iter.GetMetrics();
}

/// One UTF-8 codepoint at `index`. Invalid or cut-off bytes decode to the replacement character one
/// byte at a time, so bad text draws boxes instead of crashing or swallowing what follows.
fn DecodeAt(text: []const u8, index: usize) struct { Codepoint: u21, Len: usize } {
    const len = std.unicode.utf8ByteSequenceLength(text[index]) catch return .{ .Codepoint = REPLACEMENT_CHAR, .Len = 1 };
    if (index + len > text.len) return .{ .Codepoint = REPLACEMENT_CHAR, .Len = 1 };
    const codepoint = std.unicode.utf8Decode(text[index .. index + len]) catch return .{ .Codepoint = REPLACEMENT_CHAR, .Len = 1 };
    return .{ .Codepoint = codepoint, .Len = len };
}
