const BuiltinComponentCount = @import("../../ECS/Components.zig").BuiltinComponentCount;
const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const EngineContext = @import("../../Core/EngineContext.zig");
const GenMetaData = @This();

pub const Name: []const u8 = "GenMetaData";
pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == GenMetaData) {
            break :blk i + BuiltinComponentCount;
        }
    }
};

mLastModified: i128 = 0,

pub fn Deinit(_: *GenMetaData, _: *EngineContext) void {}
