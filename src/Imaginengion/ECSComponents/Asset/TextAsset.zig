const std = @import("std");
const AssetsList = @import("../AComponents.zig").AssetsList;
const AssetHandle = @import("../../ECSObjects/AssetHandle.zig");
const MathTypes = @import("../../Math/MathTypes.zig");
const Vec4 = MathTypes.Vec4;
const Vec2 = MathTypes.Vec2;
const EngineContext = @import("../../Core/EngineContext.zig");
const Tracy = @import("../../Core/Tracy.zig");
const Texture2D = @import("Texture2D.zig");
const TextLayout = @import("../../Renderer/TextLayout.zig");
const TextAsset = @This();

const KerningsT = std.AutoHashMap(u16, f32);

const GlyphInfo = struct {
    mAtlasTexel0: Vec2(f32) = .{ .x = -1, .y = -1 }, //top-left
    mAtlasTexel1: Vec2(f32) = .{ .x = -1, .y = -1 }, //bottom-right
    mPlaneMin: Vec2(f32) = .{ .x = -1, .y = -1 }, //left,top
    mPlaneMax: Vec2(f32) = .{ .x = -1, .y = -1 }, //right,bottom
    mAdvance: f32 = -1,
    mKernings: KerningsT = undefined,
};

const GYLPH_SET_SIZE = 2798; //note this comes from adding up all the characters from the charset.txt if that file change this number also needs to change

pub const Name: []const u8 = "TextAsset";

/// The box glyph's slot (U+25A1): what codepoints the font can't draw are drawn with
const BOX_IND = 351;

mGlyphs: [GYLPH_SET_SIZE]GlyphInfo = undefined,
mDistanceRange: u32 = 0,
mSize: u32 = 0,
mLineHeight: f32 = 0.0,
mAscender: f32 = 0.0,
mDescender: f32 = 0.0,
mEmsize: f32 = 0.0,
mAtlasSize: Vec2(f32) = .{ .x = 0, .y = 0 },
mAtlas: Texture2D = .{},
/// how far any of its glyphs can go (TextLayout.FontReach), worked out once its glyphs are read, for bounding a text
/// before laying it out (TextLayout.Reach). Null until then, which bounds nothing
mReach: ?TextLayout.FontReach = null,

/// `abs_path` is the font's, or in a packaged game its atlas .json's (AManager.PackagedPath): only the atlas's files are
/// read, from next to it. The font itself is only needed to generate them
pub fn Init(self: *TextAsset, engine_context: *EngineContext, abs_path: []const u8, rel_path: []const u8, _: std.Io.File) !void {
    //builds the font atlas, which makes this one of the slowest asset loads
    const zone = Tracy.ZoneInit("TextAsset::Init", @src());
    defer zone.Deinit();
    zone.Text(rel_path);

    const scratch_allocator = engine_context.Scratch();

    //the generated files sit next to the font, so they are built from the absolute path: the rel path is
    //relative to the project (or engine) folder, not the working directory the files are opened from
    const ext = std.fs.path.extension(abs_path);
    const base_path = abs_path[0 .. abs_path.len - ext.len];

    const name_png = try std.fmt.allocPrint(scratch_allocator, "{s}.png", .{base_path});
    const name_json = try std.fmt.allocPrint(scratch_allocator, "{s}.json", .{base_path});

    //test to see if both of the files are present already
    var file_json: ?std.Io.File = std.Io.Dir.cwd().openFile(engine_context.Io(), name_json, .{}) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
    var file_png: ?std.Io.File = std.Io.Dir.cwd().openFile(engine_context.Io(), name_png, .{}) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };

    //if one of them is missing then we generate new files using msdfgen
    if (file_png == null or file_json == null) {
        if (file_json) |f| f.close(engine_context.Io());
        if (file_png) |f| f.close(engine_context.Io());

        std.log.info("Font generated files not found for {s}.\n Generating files now.", .{rel_path});

        var child = try std.process.spawn(
            engine_context.Io(),
            .{
                .argv = &[_][]const u8{
                    "./src/Imaginengion/Vendor/msdfgen/msdf-atlas-gen.exe",
                    "-type",
                    "msdf",
                    "-font",
                    abs_path,
                    "-charset",
                    "./src/Imaginengion/EngineAssets/fonts/charset.txt",
                    "-size",
                    "64",
                    "-pxrange",
                    "4",
                    "-imageout",
                    name_png,
                    "-json",
                    name_json,
                },
                .stdin = .inherit,
                .stdout = .inherit,
                .stderr = .inherit,
            },
        );
        const result = try child.wait(engine_context.Io());

        if (result != .exited) {
            std.log.err("Unable to correctly generate text files {s}. It terminated by {s}!", .{ rel_path, @tagName(result) });
            return error.AssetInitFailed;
        }
        if (result.exited != 0) {
            std.log.err("Unable to correctly generate text files {s} exited with code {d}!", .{ rel_path, result.exited });
            return error.AssetInitFailed;
        }
        std.log.info("text {s} generated success!\n", .{rel_path});

        file_json = try std.Io.Dir.cwd().openFile(engine_context.Io(), name_json, .{});
        file_png = try std.Io.Dir.cwd().openFile(engine_context.Io(), name_png, .{});
    }
    defer file_json.?.close(engine_context.Io());
    defer file_png.?.close(engine_context.Io());

    var json_reader = file_json.?.reader(engine_context.Io(), &.{});
    const contents = try json_reader.interface.allocRemaining(scratch_allocator, .unlimited);
    try self.ReadAtlasJson(engine_context.mAssetManager.KeepFor(TextAsset), scratch_allocator, contents);

    const rel_ext = std.fs.path.extension(rel_path);
    const atlas_rel_path = try std.fmt.allocPrint(scratch_allocator, "{s}.png", .{rel_path[0 .. rel_path.len - rel_ext.len]});
    try self.mAtlas.Init(engine_context, name_png, atlas_rel_path, file_png.?);
}

/// Assets are shared through reference counted handles instead of being copied, and this one owns a GPU
/// atlas and kerning tables that have no meaningful copy. Fails loudly rather than letting the default
/// value copy alias the atlas and free it twice.
pub fn Clone(_: *const TextAsset, _: *EngineContext, _: std.mem.Allocator) !TextAsset {
    return error.AssetNotDuplicatable;
}

pub fn Deinit(self: *TextAsset, engine_context: *EngineContext, keep_allocator: std.mem.Allocator) void {
    for (self.mGlyphs, 0..) |_, i| {
        self.mGlyphs[i].mKernings.deinit();
    }
    self.mAtlas.Deinit(engine_context, keep_allocator);
}

/// What msdf-atlas-gen writes into a font's atlas .json, as far as it is read here: the rest of it is skipped
const AtlasJson = struct {
    atlas: struct {
        distanceRange: u32 = 0,
        size: u32 = 0,
        width: f32 = 0,
        height: f32 = 0,
    } = .{},
    metrics: struct {
        emSize: f32 = 0,
        lineHeight: f32 = 0,
        ascender: f32 = 0,
        descender: f32 = 0,
    } = .{},
    glyphs: []const struct {
        unicode: ?usize = null,
        advance: f32 = -1,
        /// the glyph's box at font size 1, y up. None for a glyph with no ink (a space)
        planeBounds: ?Bounds = null,
        /// where the glyph is in the atlas, in texels
        atlasBounds: ?Bounds = null,
    } = &.{},
    kerning: []const struct {
        unicode1: u16,
        unicode2: u16,
        advance: f32,
    } = &.{},

    const Bounds = struct { left: f32 = -1, bottom: f32 = -1, right: f32 = -1, top: f32 = -1 };
};

/// Takes the font's glyphs, metrics and kernings from `contents`, the atlas .json msdf-atlas-gen wrote for it. Every
/// glyph's kernings are taken from `keep_allocator`, which Deinit frees them with
pub fn ReadAtlasJson(self: *TextAsset, keep_allocator: std.mem.Allocator, scratch_allocator: std.mem.Allocator, contents: []const u8) !void {
    const file = try std.json.parseFromSliceLeaky(AtlasJson, scratch_allocator, contents, .{ .ignore_unknown_fields = true });
    self.mDistanceRange = file.atlas.distanceRange;
    self.mSize = file.atlas.size;
    self.mAtlasSize = .{ .x = file.atlas.width, .y = file.atlas.height };
    self.mEmsize = file.metrics.emSize;
    self.mLineHeight = file.metrics.lineHeight;
    self.mAscender = file.metrics.ascender;
    self.mDescender = file.metrics.descender;

    //every slot starts as no glyph (mAdvance -1), so one the font has no glyph for is never read as garbage
    for (&self.mGlyphs) |*glyph| glyph.* = .{ .mKernings = KerningsT.init(keep_allocator) };
    for (file.glyphs) |read| {
        //the glyph's corners are kept as (left, top) and (right, bottom)
        var glyph = GlyphInfo{ .mAdvance = read.advance, .mKernings = KerningsT.init(keep_allocator) };
        if (read.planeBounds) |bounds| {
            glyph.mPlaneMin = .{ .x = bounds.left, .y = bounds.top };
            glyph.mPlaneMax = .{ .x = bounds.right, .y = bounds.bottom };
        }
        if (read.atlasBounds) |bounds| {
            glyph.mAtlasTexel0 = .{ .x = bounds.left, .y = bounds.top };
            glyph.mAtlasTexel1 = .{ .x = bounds.right, .y = bounds.bottom };
        }
        self.mGlyphs[if (read.unicode) |unicode| ToArrayIndex(unicode) else 0] = glyph;
    }
    for (file.kerning) |pair| try self.mGlyphs[ToArrayIndex(pair.unicode1)].mKernings.put(pair.unicode2, pair.advance);

    //the charset has codepoints no font draws (unassigned ones, U+3130 and U+318F): they draw the box, the same as any
    //codepoint outside the charset
    const box = self.mGlyphs[BOX_IND];
    for (&self.mGlyphs) |*glyph| {
        if (glyph.mAdvance >= 0) continue;
        glyph.* = box;
        glyph.mKernings = KerningsT.init(keep_allocator);
    }
    self.mReach = TextLayout.FontReach.Of(TextAsset, self);
}

//NOTE: this to sprase index is based off of the current format of the charset.txt
//if charset.txt changes this has to as well
pub fn ToArrayIndex(unicode: usize) usize {
    const ascii_ofset = 0;
    const jamo_offset = 95;
    const box_offset = BOX_IND;
    const comp_jamo_offset = 352;
    const hangul_syllables_offset = 448;

    // 1. ASCII: [32, 126] (95 chars) -> [0, 94]
    if (unicode >= 32 and unicode <= 126) {
        return unicode - 32 + ascii_ofset;
    }

    // 2. Hangul Jamo: [4352, 4607] (256 chars) -> [95, 350]
    if (unicode >= 4352 and unicode <= 4607) {
        return unicode - 4352 + jamo_offset;
    }

    // New: 9633 (1 char) -> [351]
    if (unicode == 9633) {
        return box_offset;
    }

    // 3. Hangul Compatibility Jamo: [12592, 12687] (96 chars) -> [352, 447]
    if (unicode >= 12592 and unicode <= 12687) {
        return unicode - 12592 + comp_jamo_offset;
    }

    // 4. Hangul Syllables (2,350 common): [44032, 46381] (2350 chars) -> [448, 2797]
    if (unicode >= 44032 and unicode <= 46381) {
        return unicode - 44032 + hangul_syllables_offset;
    }

    return box_offset;
}
