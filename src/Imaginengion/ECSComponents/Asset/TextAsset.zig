const std = @import("std");
const AssetsList = @import("../AComponents.zig").AssetsList;
const AssetHandle = @import("../../ECSObjects/AssetHandle.zig");
const MathTypes = @import("../../Math/MathTypes.zig");
const Vec4 = MathTypes.Vec4;
const Vec2 = MathTypes.Vec2;
const EngineContext = @import("../../Core/EngineContext.zig");
const Tracy = @import("../../Core/Tracy.zig");
const Texture2D = @import("Texture2D.zig");
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

const PARSE_OPTIONS = std.json.ParseOptions{ .allocate = .alloc_if_needed, .max_value_len = std.json.default_max_value_len };

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

    //every slot starts as no glyph (mAdvance -1), so one the font has no glyph for is never read as garbage
    for (&self.mGlyphs) |*glyph| glyph.* = .{ .mKernings = KerningsT.init(engine_context.Keep()) };
    try self.ProcessTextJson(engine_context, file_json.?);
    //the charset has codepoints no font draws (unassigned ones, U+3130 and U+318F): they draw the box, the same as any
    //codepoint outside the charset
    const box = self.mGlyphs[BOX_IND];
    for (&self.mGlyphs) |*glyph| {
        if (glyph.mAdvance >= 0) continue;
        glyph.* = box;
        glyph.mKernings = KerningsT.init(engine_context.Keep());
    }

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

fn ProcessTextJson(self: *TextAsset, engine_context: *EngineContext, text_json: std.Io.File) !void {
    const scratch_allocator = engine_context.Scratch();

    var file_reader = text_json.reader(engine_context.Io(), &.{});
    const contents = try file_reader.interface.allocRemaining(scratch_allocator, .unlimited);

    var the_reader: std.Io.Reader = .fixed(contents);

    var reader = std.json.Reader.init(scratch_allocator, &the_reader);
    defer reader.deinit();

    //deserialize
    while (true) {
        const token = try reader.next();
        const token_value = try switch (token) {
            .end_of_document => break,
            .object_begin => continue,
            .object_end => continue,
            .string => |value| value,
            .number => |value| value,

            else => error.NotExpected,
        };

        const actual_value = try scratch_allocator.dupe(u8, token_value);
        defer scratch_allocator.free(actual_value);

        if (std.mem.eql(u8, actual_value, "atlas")) {
            try self.ProcessAtlas(&reader, scratch_allocator);
        } else if (std.mem.eql(u8, actual_value, "metrics")) {
            try self.ProcessMetrics(&reader, scratch_allocator);
        } else if (std.mem.eql(u8, actual_value, "glyphs")) {
            try self.ProcessGlyphs(engine_context.Keep(), &reader, scratch_allocator);
        } else if (std.mem.eql(u8, actual_value, "kerning")) {
            try self.ProcessKerning(&reader, scratch_allocator);
        }
    }
}

fn ProcessAtlas(self: *TextAsset, reader: *std.json.Reader, scratch_allocator: std.mem.Allocator) !void {
    try SkipToken(reader); //skip the begin object for the atlas
    while (true) {
        const token = try reader.next();
        const token_value = try switch (token) {
            .object_end => break,
            .string => |value| value,
            .number => |value| value,

            else => error.NotExpected,
        };

        const actual_value = try scratch_allocator.dupe(u8, token_value);
        defer scratch_allocator.free(actual_value);

        if (std.mem.eql(u8, actual_value, "distanceRange")) {
            const parsed_value = try std.json.innerParse(u32, scratch_allocator, reader, PARSE_OPTIONS);
            self.mDistanceRange = parsed_value;
        } else if (std.mem.eql(u8, actual_value, "size")) {
            const parsed_value = try std.json.innerParse(u32, scratch_allocator, reader, PARSE_OPTIONS);
            self.mSize = parsed_value;
        } else if (std.mem.eql(u8, actual_value, "width")) {
            const parsed_value = try std.json.innerParse(f32, scratch_allocator, reader, PARSE_OPTIONS);
            self.mAtlasSize.x = parsed_value;
        } else if (std.mem.eql(u8, actual_value, "height")) {
            const parsed_value = try std.json.innerParse(f32, scratch_allocator, reader, PARSE_OPTIONS);
            self.mAtlasSize.y = parsed_value;
        }
    }
}

fn ProcessMetrics(self: *TextAsset, reader: *std.json.Reader, scratch_allocator: std.mem.Allocator) !void {
    try SkipToken(reader); //skip the begin object for the metrics
    while (true) {
        const token = try reader.next();
        const token_value = try switch (token) {
            .object_end => break,
            .string => |value| value,
            .number => |value| value,

            else => error.NotExpected,
        };

        const actual_value = try scratch_allocator.dupe(u8, token_value);
        defer scratch_allocator.free(actual_value);

        if (std.mem.eql(u8, actual_value, "emSize")) {
            const parsed_value = try std.json.innerParse(f32, scratch_allocator, reader, PARSE_OPTIONS);
            self.mEmsize = parsed_value;
        } else if (std.mem.eql(u8, actual_value, "lineHeight")) {
            const parsed_value = try std.json.innerParse(f32, scratch_allocator, reader, PARSE_OPTIONS);
            self.mLineHeight = parsed_value;
        } else if (std.mem.eql(u8, actual_value, "ascender")) {
            const parsed_value = try std.json.innerParse(f32, scratch_allocator, reader, PARSE_OPTIONS);
            self.mAscender = parsed_value;
        } else if (std.mem.eql(u8, actual_value, "descender")) {
            const parsed_value = try std.json.innerParse(f32, scratch_allocator, reader, PARSE_OPTIONS);
            self.mDescender = parsed_value;
        }
    }
}
fn ProcessGlyphs(self: *TextAsset, keep_allocator: std.mem.Allocator, reader: *std.json.Reader, scratch_allocator: std.mem.Allocator) !void {
    try SkipToken(reader); //skip the begin array

    while (true) {
        const token = try reader.next();
        switch (token) {
            .array_end => break,
            .object_begin => {},
            else => return error.NotExpected,
        }
        var new_glyph = GlyphInfo{
            .mKernings = KerningsT.init(keep_allocator),
        };
        var glyph_ind: usize = 0;
        try SingleGlyph(reader, &glyph_ind, &new_glyph, scratch_allocator);
        if (glyph_ind > -1) {
            self.mGlyphs[@intCast(glyph_ind)] = new_glyph;
        }
    }
}

fn SingleGlyph(reader: *std.json.Reader, glyph_ind: *usize, new_glyph: *GlyphInfo, scratch_allocator: std.mem.Allocator) !void {
    while (true) {
        const token = try reader.next();
        const token_value = try switch (token) {
            .object_end => break,
            .string => |value| value,
            .number => |value| value,

            else => error.NotExpected,
        };
        const actual_value = try scratch_allocator.dupe(u8, token_value);
        defer scratch_allocator.free(actual_value);

        if (std.mem.eql(u8, actual_value, "unicode")) {
            const parsed_value = try std.json.innerParse(usize, scratch_allocator, reader, PARSE_OPTIONS);
            glyph_ind.* = ToArrayIndex(parsed_value);
        } else if (std.mem.eql(u8, actual_value, "advance")) {
            const parsed_value = try std.json.innerParse(f32, scratch_allocator, reader, PARSE_OPTIONS);
            new_glyph.mAdvance = parsed_value;
        } else if (std.mem.eql(u8, actual_value, "planeBounds")) {
            try ProcessPlaneBounds(reader, new_glyph, scratch_allocator);
        } else if (std.mem.eql(u8, actual_value, "atlasBounds")) {
            try ProcessAtlasBounds(reader, new_glyph, scratch_allocator);
        }
    }
}

fn ProcessPlaneBounds(reader: *std.json.Reader, new_glyph: *GlyphInfo, scratch_allocator: std.mem.Allocator) !void {
    try SkipToken(reader); //skip the begin object token
    while (true) {
        const token = try reader.next();
        const token_value = try switch (token) {
            .object_end => break,
            .string => |value| value,
            .number => |value| value,

            else => error.NotExpected,
        };

        const actual_value = try scratch_allocator.dupe(u8, token_value);
        defer scratch_allocator.free(actual_value);

        if (std.mem.eql(u8, actual_value, "left")) {
            const parsed_value = try std.json.innerParse(f32, scratch_allocator, reader, PARSE_OPTIONS);
            new_glyph.mPlaneMin.x = parsed_value;
        } else if (std.mem.eql(u8, actual_value, "bottom")) {
            const parsed_value = try std.json.innerParse(f32, scratch_allocator, reader, PARSE_OPTIONS);
            new_glyph.mPlaneMax.y = parsed_value;
        } else if (std.mem.eql(u8, actual_value, "right")) {
            const parsed_value = try std.json.innerParse(f32, scratch_allocator, reader, PARSE_OPTIONS);
            new_glyph.mPlaneMax.x = parsed_value;
        } else if (std.mem.eql(u8, actual_value, "top")) {
            const parsed_value = try std.json.innerParse(f32, scratch_allocator, reader, PARSE_OPTIONS);
            new_glyph.mPlaneMin.y = parsed_value;
        }
    }
}

fn ProcessAtlasBounds(reader: *std.json.Reader, new_glyph: *GlyphInfo, scratch_allocator: std.mem.Allocator) !void {
    try SkipToken(reader); //skip the begin object token
    while (true) {
        const token = try reader.next();
        const token_value = try switch (token) {
            .object_end => break,
            .string => |value| value,
            .number => |value| value,

            else => error.NotExpected,
        };

        const actual_value = try scratch_allocator.dupe(u8, token_value);
        defer scratch_allocator.free(actual_value);

        if (std.mem.eql(u8, actual_value, "left")) {
            const parsed_value = try std.json.innerParse(f32, scratch_allocator, reader, PARSE_OPTIONS);
            new_glyph.mAtlasTexel0.x = parsed_value;
        } else if (std.mem.eql(u8, actual_value, "bottom")) {
            const parsed_value = try std.json.innerParse(f32, scratch_allocator, reader, PARSE_OPTIONS);
            new_glyph.mAtlasTexel1.y = parsed_value;
        } else if (std.mem.eql(u8, actual_value, "right")) {
            const parsed_value = try std.json.innerParse(f32, scratch_allocator, reader, PARSE_OPTIONS);
            new_glyph.mAtlasTexel1.x = parsed_value;
        } else if (std.mem.eql(u8, actual_value, "top")) {
            const parsed_value = try std.json.innerParse(f32, scratch_allocator, reader, PARSE_OPTIONS);
            new_glyph.mAtlasTexel0.y = parsed_value;
        }
    }
}

fn ProcessKerning(self: *TextAsset, reader: *std.json.Reader, scratch_allocator: std.mem.Allocator) !void {
    try SkipToken(reader); //skip the begin array

    while (true) {
        const token = try reader.next();
        switch (token) {
            .array_end => break,
            .object_begin => {},
            else => return error.NotExpected,
        }

        try self.SingleKerning(reader, scratch_allocator);
    }
}

fn SingleKerning(self: *TextAsset, reader: *std.json.Reader, scratch_allocator: std.mem.Allocator) !void {

    //unicode1
    const token1 = try reader.next();
    const token_value1 = try switch (token1) {
        .string => |value| value,
        .number => |value| value,

        else => error.NotExpected,
    };

    const actual_value1 = try scratch_allocator.dupe(u8, token_value1);
    defer scratch_allocator.free(actual_value1);

    const unicode1 = try std.json.innerParse(u16, scratch_allocator, reader, PARSE_OPTIONS);
    const glyph_ind1 = ToArrayIndex(unicode1);

    //unicode2
    const token2 = try reader.next();
    const token_value2 = try switch (token2) {
        .string => |value| value,
        .number => |value| value,

        else => error.NotExpected,
    };

    const actual_value2 = try scratch_allocator.dupe(u8, token_value2);
    defer scratch_allocator.free(actual_value2);

    const unicode2 = try std.json.innerParse(u16, scratch_allocator, reader, PARSE_OPTIONS);

    const token3 = try reader.next();
    const token_value3 = try switch (token3) {
        .string => |value| value,
        .number => |value| value,

        else => error.NotExpected,
    };

    const actual_value3 = try scratch_allocator.dupe(u8, token_value3);
    defer scratch_allocator.free(actual_value3);

    const advance = try std.json.innerParse(f32, scratch_allocator, reader, PARSE_OPTIONS);

    try self.mGlyphs[glyph_ind1].mKernings.put(unicode2, advance);
    try SkipToken(reader); //skip the end object token
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

fn SkipToken(reader: *std.json.Reader) !void {
    _ = try reader.next();
}
