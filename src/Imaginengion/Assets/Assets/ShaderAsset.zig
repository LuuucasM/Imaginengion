const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const Shader = @import("../../Shaders/Shader.zig");
const imgui = @import("../../Core/CImports.zig").imgui;
const ShaderAsset = @This();
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;

mShader: Shader = undefined,

pub fn Init(allocator: std.mem.Allocator, asset_file: std.fs.File, rel_path: []const u8) !ShaderAsset {
    return ShaderAsset{
        .mShader = try Shader.Init(allocator, asset_file, rel_path),
    };
}

pub fn Deinit(self: *ShaderAsset) !void {
    self.mShader.Deinit();
}

pub fn EditorRender(self: *ShaderAsset) !void {
    _ = self;
    imgui.igText("Nothing for now!", "");
}

pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == ShaderAsset) {
            break :blk i;
        }
    }
};

pub const Category: ComponentCategory = .Unique;
