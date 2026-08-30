const std = @import("std");
const ComponentsList = @import("../AComponents.zig").ComponentsList;
const PlayerAsset = @This();
const EngineContext = @import("../../Core/EngineContext.zig");
const Player = @import("../../ECSObjects/Player.zig");

pub const empty: PlayerAsset = .{
    .mPlayer = .empty,
};

mPlayer: Player,

pub fn Deinit(_: *PlayerAsset, _: *EngineContext) !void {}

pub const Name: []const u8 = "PlayerAsset";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |asset_type, i| {
        if (asset_type == PlayerAsset) {
            break :blk i + 5;
        }
    }
};
