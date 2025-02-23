const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const Script = @This();

mLib: std.DynLib,

pub fn Init(path: []const u8) !Script {
    return Script{ .mLib = std.DynLib.open() };
}

pub fn Deinit(self: Script) void {
    self.mFile.close();
}

pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == Script) {
            break :blk i;
        }
    }
};
