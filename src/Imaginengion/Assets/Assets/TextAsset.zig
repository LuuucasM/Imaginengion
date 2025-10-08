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
    mPlaneBounds: Vec4f32 = Vec4f32{ -1, -1, -1, -1 },
    mUVBounds: Vec4f32 = Vec4f32{ -1, -1, -1, -1 }, //bounds 0 and 1 are x and y for bottom left, 2 and 3 are x and y for top right for uv bounds
    mAdvance: f32 = -1,
    mKernings: KerningsT = undefined,
};
const GlyphSetT = SparseSet(.{
    .SparseT = u16,
    .DenseT = u16,
    .ValueT = GlyphInfo,
    .value_layout = .InternalArrayOfStructs,
    .allow_resize = .ResizeAllowed,
});

const PARSE_OPTIONS = std.json.ParseOptions{ .allocate = .alloc_if_needed, .max_value_len = std.json.default_max_value_len };

const SPARSE_SET_SIZE = 2797; //note this comes from adding up all the characters from the charset.txt if that file change this number also needs to change

pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == TextAsset) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

pub const Category: ComponentCategory = .Unique;

mTextureAtlas: AssetHandle = undefined,
mGlyphs: GlyphSetT = undefined,
mDistanceRange: u32 = 0,
mSize: u32 = 0,
mAllocator: std.mem.Allocator = undefined,
mLineHeight: f32 = 0.0,
mAscender: f32 = 0.0,
mDescender: f32 = 0.0,
mEmsize: f32 = 0.0,

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
    if (self.mTextureAtlas.mID != AssetHandle.NullHandle) AssetManager.ReleaseAssetHandleRef(&self.mTextureAtlas);
    var i: usize = 0;
    while (i < self.mGlyphs.dense_count) : (i += 1) {
        self.mGlyphs.values[i].mKernings.deinit();
    }
    self.mGlyphs.deinit();
}

fn ProcessTextJson(asset_allocator: std.mem.Allocator, arena_allocator: std.mem.Allocator, text_json: std.fs.File) !TextAsset {
    var new_text_asset = TextAsset{
        .mAllocator = asset_allocator,
        .mGlyphs = try GlyphSetT.init(asset_allocator, SPARSE_SET_SIZE + 1, SPARSE_SET_SIZE),
    };

    const file_size = try text_json.getEndPos();

    var file_contents = try std.ArrayList(u8).initCapacity(arena_allocator, file_size);
    try file_contents.resize(arena_allocator, file_size);
    _ = try text_json.readAll(file_contents.items);

    std.debug.print("file contents size: {}\n", .{file_contents.items.len});
    var io_reader = std.io.Reader.fixed(file_contents.items);

    var reader = std.json.Reader.init(arena_allocator, &io_reader);
    defer reader.deinit();

    var atlas_size: Vec2f32 = Vec2f32{ 0.0, 0.0 };

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
            try ProcessAtlas(&reader, &new_text_asset, &atlas_size, arena_allocator);
            std.debug.print("i do this\n", .{});
        } else if (std.mem.eql(u8, actual_value, "metrics")) {
            try ProcessMetrics(&reader, &new_text_asset, arena_allocator);
            std.debug.print("i do this2\n", .{});
        } else if (std.mem.eql(u8, actual_value, "glyphs")) {
            try ProcessGlyphs(&reader, &new_text_asset, atlas_size, arena_allocator, asset_allocator);
            std.debug.print("i do this3\n", .{});
        } else if (std.mem.eql(u8, actual_value, "kerning")) {
            try ProcessKerning(&reader, &new_text_asset, arena_allocator);
            std.debug.print("i do this4\n", .{});
        }
    }

    return new_text_asset;
}

fn ProcessAtlas(reader: *std.json.Reader, new_text_asset: *TextAsset, atlas_size: *Vec2f32, arena_allocator: std.mem.Allocator) !void {
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
            atlas_size[0] = parsed_value;
        } else if (std.mem.eql(u8, actual_value, "height")) {
            const parsed_value = try std.json.innerParse(f32, arena_allocator, reader, PARSE_OPTIONS);
            atlas_size[1] = parsed_value;
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
fn ProcessGlyphs(reader: *std.json.Reader, new_text_asset: *TextAsset, atlas_size: Vec2f32, arena_allocator: std.mem.Allocator, asset_allocator: std.mem.Allocator) !void {
    try SkipToken(reader); //skip the begin array

    while (true) {
        const token = try reader.next();
        switch (token) {
            .array_end => break,
            .object_begin => {},
            else => return error.NotExpected,
        }
        var new_glyph = GlyphInfo{
            .mKernings = KerningsT.init(asset_allocator),
        };
        var unicode: i32 = 0;
        try SingleGlyph(reader, &unicode, &new_glyph, atlas_size, arena_allocator);
        if (unicode > -1) {
            _ = new_text_asset.mGlyphs.addValue(@intCast(unicode), new_glyph);
        }
    }
}

fn SingleGlyph(reader: *std.json.Reader, unicode: *i32, new_glyph: *GlyphInfo, atlas_size: Vec2f32, arena_allocator: std.mem.Allocator) !void {
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
            const parsed_value = try std.json.innerParse(i32, arena_allocator, reader, PARSE_OPTIONS);
            unicode.* = ToSparseIndex(parsed_value);
        } else if (std.mem.eql(u8, actual_value, "advance")) {
            const parsed_value = try std.json.innerParse(f32, arena_allocator, reader, PARSE_OPTIONS);
            new_glyph.mAdvance = parsed_value;
        } else if (std.mem.eql(u8, actual_value, "planeBounds")) {
            try ProcessPlaneBounds(reader, new_glyph, arena_allocator);
        } else if (std.mem.eql(u8, actual_value, "atlasBounds")) {
            try ProcessAtlasBounds(reader, new_glyph, atlas_size, arena_allocator);
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
            new_glyph.mPlaneBounds[1] = parsed_value;
        } else if (std.mem.eql(u8, actual_value, "right")) {
            const parsed_value = try std.json.innerParse(f32, arena_allocator, reader, PARSE_OPTIONS);
            new_glyph.mPlaneBounds[2] = parsed_value;
        } else if (std.mem.eql(u8, actual_value, "top")) {
            const parsed_value = try std.json.innerParse(f32, arena_allocator, reader, PARSE_OPTIONS);
            new_glyph.mPlaneBounds[3] = parsed_value;
        }
    }
}

fn ProcessAtlasBounds(reader: *std.json.Reader, new_glyph: *GlyphInfo, atlas_size: Vec2f32, arena_allocator: std.mem.Allocator) !void {
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
            new_glyph.mUVBounds[0] = parsed_value / atlas_size[0];
        } else if (std.mem.eql(u8, actual_value, "bottom")) {
            const parsed_value = try std.json.innerParse(f32, arena_allocator, reader, PARSE_OPTIONS);
            new_glyph.mUVBounds[1] = parsed_value / atlas_size[1];
        } else if (std.mem.eql(u8, actual_value, "right")) {
            const parsed_value = try std.json.innerParse(f32, arena_allocator, reader, PARSE_OPTIONS);
            new_glyph.mUVBounds[2] = parsed_value / atlas_size[0];
        } else if (std.mem.eql(u8, actual_value, "top")) {
            const parsed_value = try std.json.innerParse(f32, arena_allocator, reader, PARSE_OPTIONS);
            new_glyph.mUVBounds[3] = parsed_value / atlas_size[1];
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

    if (new_text_asset.mGlyphs.hasSparse(unicode1) and new_text_asset.mGlyphs.hasSparse(unicode2)) {
        //advance
        const token3 = try reader.next();
        const token_value3 = try switch (token3) {
            .string => |value| value,
            .number => |value| value,

            else => error.NotExpected,
        };

        const actual_value3 = try arena_allocator.dupe(u8, token_value3);
        defer arena_allocator.free(actual_value3);

        const advance = try std.json.innerParse(f32, arena_allocator, reader, PARSE_OPTIONS);

        var glyph_info = new_text_asset.mGlyphs.getValueBySparse(unicode1);
        try glyph_info.mKernings.put(unicode2, advance);
    }

    try SkipToken(reader); //skip the end object token
}

//NOTE: this to sprase index is based off of the current format of the charset.txt
//if charset.txt changes this has to as well
fn ToSparseIndex(unicode: i32) i32 {
    const ascii_ofset = 0;
    const jamo_offset = 95;
    const comp_jamo_offset = 351;
    const hangul_syllables_offset = 447;
    // 1. ASCII: [32, 126]
    if (unicode >= 32 and unicode <= 126) {
        return unicode - 32 + ascii_ofset;
    }

    // 2. Hangul Jamo: [4352, 4607]
    if (unicode >= 4352 and unicode <= 4607) {
        return unicode - 4352 + jamo_offset;
    }

    // 3. Hangul Compatibility Jamo: [12592, 12687]
    if (unicode >= 12592 and unicode <= 12687) {
        return unicode - 12592 + comp_jamo_offset;
    }

    // 4. Hangul Syllables (2,350 common): [44032, 46381]
    if (unicode >= 44032 and unicode <= 46381) {
        return unicode - 44032 + hangul_syllables_offset;
    }
    return -1;
}

fn SkipToken(reader: *std.json.Reader) !void {
    _ = try reader.next();
}
