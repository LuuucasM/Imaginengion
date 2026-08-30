const std = @import("std");
const ComponentsList = @import("../AComponents.zig").ComponentsList;
const GCAsset = @This();
const EngineContext = @import("../../Core/EngineContext.zig");
const GameContext = @import("../../ECSObjects/GameContext.zig");

pub const empty: GCAsset = .{
    .mGameContext = .empty,
};

mGameContext: GameContext,

pub fn Deinit(_: *GCAsset, _: *EngineContext) !void {}

pub const Name: []const u8 = "GCAsset";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |asset_type, i| {
        if (asset_type == GCAsset) {
            break :blk i + 5;
        }
    }
};
