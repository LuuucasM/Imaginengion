const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const SceneAsset = @This();
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;
const EngineContext = @import("../../Core/EngineContext.zig");

const imgui = @import("../../Core/CImports.zig").imgui;

mSceneContents: std.ArrayList(u8) = .{},

pub fn Init(self: *SceneAsset, engine_context: EngineContext, _: []const u8, _: []const u8, asset_file: std.fs.File) !void {
    const file_size = try asset_file.getEndPos();
    self.mSceneContents = try std.ArrayList(u8).initCapacity(engine_context.mEngineAllocator, file_size);
    try self.mSceneContents.resize(engine_context.mEngineAllocator, file_size);

    _ = try asset_file.readAll(self.mSceneContents.items);
}

pub fn Deinit(self: *SceneAsset, engine_context: EngineContext) !void {
    self.mSceneContents.deinit(engine_context.mEngineAllocator);
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
