const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;
const LinAlg = @import("../../Math/LinAlg.zig");
const AssetHandle = @import("../AssetHandle.zig");
const Texture2D = @import("Texture2D.zig");
const SparseSet = @import("../../Vendor/zig-sparse-set/src/sparse_set.zig").SparseSet;
const Vec4f32 = LinAlg.Vec4f32;
const Vec2f32 = LinAlg.Vec2f32;
const AssetManager = @import("../AssetManager.zig");
const TextAsset = @This();

const GlyphInfo = struct {
    mPlaneBounds: Vec4f32,
    mAtlasBounds: Vec4f32,
    mAdvance: f32,
};

const GlyphSetT = SparseSet(.{
    .SparseT = u16,
    .DenseT = u16,
    .ValueT = GlyphInfo,
    .value_layout = .InternalArrayOfStructs,
    .allow_resize = .ResizeAllowed,
});

pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == TextAsset) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

pub const Category: ComponentCategory = .Unique;

mTextureAtlas: ?AssetHandle = null,
mGlyphs: GlyphSetT = undefined,
mAtlasSize: Vec2f32 = Vec2f32{ 1920, 1080 },
mAllocator: std.mem.Allocator = undefined,

pub fn Init(allocator: std.mem.Allocator, abs_path: []const u8, rel_path: []const u8, _: std.fs.File) !TextAsset {
    const file_path = std.fs.path.dirname(rel_path).?;
    const name = std.fs.path.stem(std.fs.path.basename(rel_path));

    var buff: [260]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buff);
    const fba_allocator = fba.allocator();

    const name_png = try std.fmt.allocPrint(fba_allocator, "{s}/{s}.png", .{ file_path, name });
    const name_json = try std.fmt.allocPrint(fba_allocator, "{s}/{s}.json", .{ file_path, name });

    var file_png = std.fs.cwd().openFile(name_png, .{}) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };

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
            allocator,
        );
        child.stdin_behavior = .Inherit;
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;

        try child.spawn();
        const result = try child.wait();
        std.log.debug("child [{s}] exited with code {}\n", .{ abs_path, result });

        if (file_png == null) {
            file_png = try std.fs.cwd().openFile(name_png, .{});
        }
        if (file_json == null) {
            file_json = try std.fs.cwd().openFile(name_json, .{});
        }
    }

    const text_png = file_png.?;
    const text_json = file_json.?;

    defer text_png.close();
    defer text_json.close();

    //now process the json file and fill up

    return TextAsset{
        .mAllocator = allocator,
        .mGlyphs = try GlyphSetT.init(allocator, 20, 10),
        .mAtlasSize = Vec2f32{ 1920, 1080 },
        .mTextureAtlas = undefined,
    };
}

pub fn Deinit(self: *TextAsset) !void {
    if (self.mTextureAtlas) |*texture_handle| {
        AssetManager.ReleaseAssetHandleRef(texture_handle);
    }

    self.mGlyphs.deinit();
}
