const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const SceneAsset = @This();

const imgui = @import("../../Core/CImports.zig").imgui;

mSceneContents: std.ArrayList(u8) = undefined,

pub fn Init(allocator: std.mem.Allocator, asset_file: std.fs.File, rel_path: []const u8) !SceneAsset {
    _ = rel_path;
    const file_size = try asset_file.getEndPos();

    var new_scene_asset = SceneAsset{
        .mSceneContents = try std.ArrayList(u8).initCapacity(allocator, file_size),
    };
    try new_scene_asset.mSceneContents.resize(file_size);
    _ = try asset_file.readAll(new_scene_asset.mSceneContents.items);
    return new_scene_asset;
}

pub fn Deinit(self: *SceneAsset) !void {
    self.mSceneContents.deinit();
}

pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == SceneAsset) {
            break :blk i;
        }
    }
};

pub fn EditorRender(self: *SceneAsset) !void {
    _ = self;
    imgui.igText("Nothing for now!", "");
}
