const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const SceneAsset = @This();
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;

const imgui = @import("../../Core/CImports.zig").imgui;

mSceneContents: std.ArrayList(u8) = .{},

_ContentsAllocator: std.mem.Allocator = undefined,

pub fn Init(self: *SceneAsset, allocator: std.mem.Allocator, _: []const u8, rel_path: []const u8, asset_file: std.fs.File) !void {
    _ = rel_path;
    self._ContentsAllocator = allocator;

    const file_size = try asset_file.getEndPos();
    self.mSceneContents = try std.ArrayList(u8).initCapacity(allocator, file_size);
    try self.mSceneContents.resize(allocator, file_size);

    _ = try asset_file.readAll(self.mSceneContents.items);
}

pub fn Deinit(self: *SceneAsset) !void {
    self.mSceneContents.deinit(self._ContentsAllocator);
}

pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == SceneAsset) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

pub fn EditorRender(self: *SceneAsset) !void {
    _ = self;
    imgui.igText("Nothing for now!", "");
}

pub const Category: ComponentCategory = .Unique;
