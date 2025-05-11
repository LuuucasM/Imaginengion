const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const Shader = @import("../../Shaders/Shaders.zig");
const imgui = @import("../../Core/CImports.zig").imgui;
const ShaderAsset = @This();

mShader: Shader,

pub fn Init(allocator: std.mem.Allocator, abs_path: []const u8) !ShaderAsset {
    return ShaderAsset{
        .mShader = Shader.Init(allocator, abs_path),
    };
}

pub fn Deinit(self: *ShaderAsset) void {
    self.mShader.Deinit();
}

pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == ShaderAsset) {
            break :blk i;
        }
    }
};

pub fn EditorRender(self: *ShaderAsset) !void {
    _ = self;
    imgui.igText("Nothing for now!", "");
}
