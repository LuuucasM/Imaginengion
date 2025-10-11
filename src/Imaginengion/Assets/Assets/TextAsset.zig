const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;
const LinAlg = @import("../../Math/LinAlg.zig");
const AssetHandle = @import("../AssetHandle.zig");
const SparseSet = @import("../../Vendor/zig-sparse-set/src/sparse_set.zig").SparseSet;
const Vec4f32 = LinAlg.Vec4f32;
const Vec2f32 = LinAlg.Vec2f32;
const AssetManager = @import("../AssetManager.zig");
const TextAsset = @This();

const KerningsT = std.AutoHashMap(u16, f32);

const GlyphInfo = struct {
    mPlaneBounds: Vec4f32 = Vec4f32{ -1, -1, -1, -1 }, //0 == left, 1 == top, 2 == right, 1 == bottom
    mAtlasBounds: Vec4f32 = Vec4f32{ -1, -1, -1, -1 }, //bounds 0 and 1 are x and y for top left UV, 2 and 3 are x and y for bottom right UV
    mAdvance: f32 = -1,
    mKernings: KerningsT = undefined,
};

const PARSE_OPTIONS = std.json.ParseOptions{ .allocate = .alloc_if_needed, .max_value_len = std.json.default_max_value_len };

const GYLPH_SET_SIZE = 2798; //note this comes from adding up all the characters from the charset.txt if that file change this number also needs to change

pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == TextAsset) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

pub const Category: ComponentCategory = .Unique;

mGlyphs: [GYLPH_SET_SIZE]GlyphInfo = undefined,
mDistanceRange: u32 = 0,
mSize: u32 = 0,
mAssetAllocator: std.mem.Allocator = undefined,
mLineHeight: f32 = 0.0,
mAscender: f32 = 0.0,
mDescender: f32 = 0.0,
mEmsize: f32 = 0.0,
mAtlasSize: Vec2f32 = Vec2f32{ 0, 0 },

pub fn Init(asset_allocator: std.mem.Allocator, abs_path: []const u8, rel_path: []const u8, _: std.fs.File) !TextAsset {
    const file_path = std.fs.path.dirname(rel_path).?;
    const name = std.fs.path.stem(std.fs.path.basename(rel_path));

    var buff: [260]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buff);
    const fba_allocator = fba.allocator();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const name_png = try std.fmt.allocPrint(fba_allocator, "{s}/{s}.png", .{ file_path, name });
    const name_json = try std.fmt.allocPrint(fba_allocator, "{s}/{s}.json", .{ file_path, name });

    const file_png = std.fs.cwd().openFile(name_png, .{}) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };

    defer if (file_png) |file| file.close();

    var file_json = std.fs.cwd().openFile(name_json, .{}) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };

    if (file_png == null or file_json == null) {
        var child = std.process.Child.init(
            &[_][]const u8{
                "./src/Imaginengion/Vendor/msdfgen/msdf-atlas-gen.exe",
                "-type",
                "msdf",
                "-font",
                abs_path,
                "-charset",
                "assets/fonts/charset.txt",
                "-size",
                "64",
                "-pxrange",
                "4",
                "-imageout",
                name_png,
                "-json",
                name_json,
            },
            asset_allocator,
        );
        child.stdin_behavior = .Inherit;
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;

        try child.spawn();
        const result = try child.wait();
        std.log.debug("child [{s}] exited with code {}\n", .{ abs_path, result });

        if (file_json == null) {
            file_json = try std.fs.cwd().openFile(name_json, .{});
        }
    }
    const text_json = file_json.?;

    defer text_json.close();

    return try ProcessTextJson(asset_allocator, arena_allocator, text_json);
}

pub fn Deinit(self: *TextAsset) !void {
    for (self.mGlyphs, 0..) |_, i| {
        self.mGlyphs[i].mKernings.deinit();
    }
}

fn ProcessTextJson(asset_allocator: std.mem.Allocator, arena_allocator: std.mem.Allocator, text_json: std.fs.File) !TextAsset {
    var new_text_asset = TextAsset{
        .mAssetAllocator = asset_allocator,
        .mGlyphs = [_]GlyphInfo{GlyphInfo{}} ** GYLPH_SET_SIZE,
    };

    const file_size = try text_json.getEndPos();

    var file_contents = try std.ArrayList(u8).initCapacity(arena_allocator, file_size);
    try file_contents.resize(arena_allocator, file_size);
    _ = try text_json.readAll(file_contents.items);

    var io_reader = std.io.Reader.fixed(file_contents.items);

    var reader = std.json.Reader.init(arena_allocator, &io_reader);
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

        const actual_value = try arena_allocator.dupe(u8, token_value);
        defer arena_allocator.free(actual_value);

        if (std.mem.eql(u8, actual_value, "atlas")) {
            try ProcessAtlas(&reader, &new_text_asset, arena_allocator);
        } else if (std.mem.eql(u8, actual_value, "metrics")) {
            try ProcessMetrics(&reader, &new_text_asset, arena_allocator);
        } else if (std.mem.eql(u8, actual_value, "glyphs")) {
            try ProcessGlyphs(&reader, &new_text_asset, arena_allocator);
        } else if (std.mem.eql(u8, actual_value, "kerning")) {
            try ProcessKerning(&reader, &new_text_asset, arena_allocator);
        }
    }

    return new_text_asset;
}

fn ProcessAtlas(reader: *std.json.Reader, new_text_asset: *TextAsset, arena_allocator: std.mem.Allocator) !void {
    try SkipToken(reader); //skip the begin object for the atlas
    while (true) {
        const token = try reader.next();
        const token_value = try switch (token) {
            .object_end => break,
            .string => |value| value,
            .number => |value| value,

            else => error.NotExpected,
        };

        const actual_value = try arena_allocator.dupe(u8, token_value);
        defer arena_allocator.free(actual_value);

        if (std.mem.eql(u8, actual_value, "distanceRange")) {
            const parsed_value = try std.json.innerParse(u32, arena_allocator, reader, PARSE_OPTIONS);
            new_text_asset.mDistanceRange = parsed_value;
        } else if (std.mem.eql(u8, actual_value, "size")) {
            const parsed_value = try std.json.innerParse(u32, arena_allocator, reader, PARSE_OPTIONS);
            new_text_asset.mSize = parsed_value;
        } else if (std.mem.eql(u8, actual_value, "width")) {
            const parsed_value = try std.json.innerParse(f32, arena_allocator, reader, PARSE_OPTIONS);
            new_text_asset.mAtlasSize[0] = parsed_value;
        } else if (std.mem.eql(u8, actual_value, "height")) {
            const parsed_value = try std.json.innerParse(f32, arena_allocator, reader, PARSE_OPTIONS);
            new_text_asset.mAtlasSize[1] = parsed_value;
        }
    }
}

fn ProcessMetrics(reader: *std.json.Reader, new_text_asset: *TextAsset, arena_allocator: std.mem.Allocator) !void {
    try SkipToken(reader); //skip the begin object for the metrics
    while (true) {
        const token = try reader.next();
        const token_value = try switch (token) {
            .object_end => break,
            .string => |value| value,
            .number => |value| value,

            else => error.NotExpected,
        };

        const actual_value = try arena_allocator.dupe(u8, token_value);
        defer arena_allocator.free(actual_value);

        if (std.mem.eql(u8, actual_value, "emSize")) {
            const parsed_value = try std.json.innerParse(f32, arena_allocator, reader, PARSE_OPTIONS);
            new_text_asset.mEmsize = parsed_value;
        } else if (std.mem.eql(u8, actual_value, "lineHeight")) {
            const parsed_value = try std.json.innerParse(f32, arena_allocator, reader, PARSE_OPTIONS);
            new_text_asset.mLineHeight = parsed_value;
        } else if (std.mem.eql(u8, actual_value, "ascender")) {
            const parsed_value = try std.json.innerParse(f32, arena_allocator, reader, PARSE_OPTIONS);
            new_text_asset.mAscender = parsed_value;
        } else if (std.mem.eql(u8, actual_value, "descender")) {
            const parsed_value = try std.json.innerParse(f32, arena_allocator, reader, PARSE_OPTIONS);
            new_text_asset.mDescender = parsed_value;
        }
    }
}
fn ProcessGlyphs(reader: *std.json.Reader, new_text_asset: *TextAsset, arena_allocator: std.mem.Allocator) !void {
    try SkipToken(reader); //skip the begin array

    while (true) {
        const token = try reader.next();
        switch (token) {
            .array_end => break,
            .object_begin => {},
            else => return error.NotExpected,
        }
        var new_glyph = GlyphInfo{
            .mKernings = KerningsT.init(new_text_asset.mAssetAllocator),
        };
        var glyph_ind: usize = 0;
        try SingleGlyph(reader, &glyph_ind, &new_glyph, arena_allocator);
        if (glyph_ind > -1) {
            new_text_asset.mGlyphs[@intCast(glyph_ind)] = new_glyph;
        }
    }
}

fn SingleGlyph(reader: *std.json.Reader, glyph_ind: *usize, new_glyph: *GlyphInfo, arena_allocator: std.mem.Allocator) !void {
    while (true) {
        const token = try reader.next();
        const token_value = try switch (token) {
            .object_end => break,
            .string => |value| value,
            .number => |value| value,

            else => error.NotExpected,
        };
        const actual_value = try arena_allocator.dupe(u8, token_value);
        defer arena_allocator.free(actual_value);

        if (std.mem.eql(u8, actual_value, "unicode")) {
            const parsed_value = try std.json.innerParse(usize, arena_allocator, reader, PARSE_OPTIONS);
            glyph_ind.* = ToArrayIndex(parsed_value);
        } else if (std.mem.eql(u8, actual_value, "advance")) {
            const parsed_value = try std.json.innerParse(f32, arena_allocator, reader, PARSE_OPTIONS);
            new_glyph.mAdvance = parsed_value;
        } else if (std.mem.eql(u8, actual_value, "planeBounds")) {
            try ProcessPlaneBounds(reader, new_glyph, arena_allocator);
        } else if (std.mem.eql(u8, actual_value, "atlasBounds")) {
            try ProcessAtlasBounds(reader, new_glyph, arena_allocator);
        }
    }
}

fn ProcessPlaneBounds(reader: *std.json.Reader, new_glyph: *GlyphInfo, arena_allocator: std.mem.Allocator) !void {
    try SkipToken(reader); //skip the begin object token
    while (true) {
        const token = try reader.next();
        const token_value = try switch (token) {
            .object_end => break,
            .string => |value| value,
            .number => |value| value,

            else => error.NotExpected,
        };

        const actual_value = try arena_allocator.dupe(u8, token_value);
        defer arena_allocator.free(actual_value);

        if (std.mem.eql(u8, actual_value, "left")) {
            const parsed_value = try std.json.innerParse(f32, arena_allocator, reader, PARSE_OPTIONS);
            new_glyph.mPlaneBounds[0] = parsed_value;
        } else if (std.mem.eql(u8, actual_value, "bottom")) {
            const parsed_value = try std.json.innerParse(f32, arena_allocator, reader, PARSE_OPTIONS);
            new_glyph.mPlaneBounds[3] = parsed_value;
        } else if (std.mem.eql(u8, actual_value, "right")) {
            const parsed_value = try std.json.innerParse(f32, arena_allocator, reader, PARSE_OPTIONS);
            new_glyph.mPlaneBounds[2] = parsed_value;
        } else if (std.mem.eql(u8, actual_value, "top")) {
            const parsed_value = try std.json.innerParse(f32, arena_allocator, reader, PARSE_OPTIONS);
            new_glyph.mPlaneBounds[1] = parsed_value;
        }
    }
}

fn ProcessAtlasBounds(reader: *std.json.Reader, new_glyph: *GlyphInfo, arena_allocator: std.mem.Allocator) !void {
    try SkipToken(reader); //skip the begin object token
    while (true) {
        const token = try reader.next();
        const token_value = try switch (token) {
            .object_end => break,
            .string => |value| value,
            .number => |value| value,

            else => error.NotExpected,
        };

        const actual_value = try arena_allocator.dupe(u8, token_value);
        defer arena_allocator.free(actual_value);

        if (std.mem.eql(u8, actual_value, "left")) {
            const parsed_value = try std.json.innerParse(f32, arena_allocator, reader, PARSE_OPTIONS);
            new_glyph.mAtlasBounds[0] = parsed_value;
        } else if (std.mem.eql(u8, actual_value, "bottom")) {
            const parsed_value = try std.json.innerParse(f32, arena_allocator, reader, PARSE_OPTIONS);
            new_glyph.mAtlasBounds[3] = parsed_value;
        } else if (std.mem.eql(u8, actual_value, "right")) {
            const parsed_value = try std.json.innerParse(f32, arena_allocator, reader, PARSE_OPTIONS);
            new_glyph.mAtlasBounds[2] = parsed_value;
        } else if (std.mem.eql(u8, actual_value, "top")) {
            const parsed_value = try std.json.innerParse(f32, arena_allocator, reader, PARSE_OPTIONS);
            new_glyph.mAtlasBounds[1] = parsed_value;
        }
    }
}

fn ProcessKerning(reader: *std.json.Reader, new_text_asset: *TextAsset, arena_allocator: std.mem.Allocator) !void {
    try SkipToken(reader); //skip the begin array

    while (true) {
        const token = try reader.next();
        switch (token) {
            .array_end => break,
            .object_begin => {},
            else => return error.NotExpected,
        }

        try SingleKerning(reader, new_text_asset, arena_allocator);
    }
}

fn SingleKerning(reader: *std.json.Reader, new_text_asset: *TextAsset, arena_allocator: std.mem.Allocator) !void {

    //unicode1
    const token1 = try reader.next();
    const token_value1 = try switch (token1) {
        .string => |value| value,
        .number => |value| value,

        else => error.NotExpected,
    };

    const actual_value1 = try arena_allocator.dupe(u8, token_value1);
    defer arena_allocator.free(actual_value1);

    const unicode1 = try std.json.innerParse(u16, arena_allocator, reader, PARSE_OPTIONS);
    const glyph_ind1 = ToArrayIndex(unicode1);

    //unicode2
    const token2 = try reader.next();
    const token_value2 = try switch (token2) {
        .string => |value| value,
        .number => |value| value,

        else => error.NotExpected,
    };

    const actual_value2 = try arena_allocator.dupe(u8, token_value2);
    defer arena_allocator.free(actual_value2);

    const unicode2 = try std.json.innerParse(u16, arena_allocator, reader, PARSE_OPTIONS);

    const token3 = try reader.next();
    const token_value3 = try switch (token3) {
        .string => |value| value,
        .number => |value| value,

        else => error.NotExpected,
    };

    const actual_value3 = try arena_allocator.dupe(u8, token_value3);
    defer arena_allocator.free(actual_value3);

    const advance = try std.json.innerParse(f32, arena_allocator, reader, PARSE_OPTIONS);

    try new_text_asset.mGlyphs[glyph_ind1].mKernings.put(unicode2, advance);
    try SkipToken(reader); //skip the end object token
}

//NOTE: this to sprase index is based off of the current format of the charset.txt
//if charset.txt changes this has to as well
pub fn ToArrayIndex(unicode: usize) usize {
    const ascii_ofset = 0;
    const jamo_offset = 95;
    const box_offset = 351;
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

    @panic("it should not get here!");
}

fn SkipToken(reader: *std.json.Reader) !void {
    _ = try reader.next();
}
