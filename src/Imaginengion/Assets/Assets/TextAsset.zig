const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;
const LinAlg = @import("../../Math/LinAlg.zig");
const AssetHandle = @import("../AssetHandle.zig");
const Texture2D = @import("Texture2D.zig");
const SparseSet = @import("../../Vendor/zig-sparse-set/src/sparse_set.zig");
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

mPath: std.ArrayList(u8) = .{},
mTextureAtlas: AssetHandle,
mGlyphs: GlyphSetT,
mAtlasSize: Vec2f32,
mAllocator: std.mem.Allocator,

pub fn Init(allocator: std.mem.Allocator, asset_file: std.fs.File, rel_path: []const u8) !TextAsset {}

pub fn Deinit(self: TextAsset) !void {
    AssetManager.ReleaseAssetHandleRef(self.mTextureAtlas);
    self.mPath.deinit(self.mAllocator);
    self.mGlyphs.deinit();
}
