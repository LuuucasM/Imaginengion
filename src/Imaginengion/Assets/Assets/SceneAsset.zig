const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const SceneAsset = @This();

const imgui = @import("../../Core/CImports.zig").imgui;

mSceneContents: std.ArrayList(u8) = undefined,

pub fn Init(allocator: std.mem.Allocator, abs_path: []const u8) !SceneAsset {
    const file = try std.fs.openFileAbsolute(abs_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();

    const new_scene_asset = SceneAsset{
        .mSceneContents = try std.ArrayList(u8).initCapacity(allocator, file_size),
    };

    _ = try file.readAll(new_scene_asset.mSceneContents.items);

    return new_scene_asset;
}

pub fn Deinit(self: *SceneAsset) void {
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
