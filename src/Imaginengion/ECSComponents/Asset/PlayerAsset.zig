const std = @import("std");
const PlayerAsset = @This();
const EngineContext = @import("../../Core/EngineContext.zig");
const Player = @import("../../ECSObjects/Player.zig");

pub const empty: PlayerAsset = .{
    .mPlayer = .empty,
};

mPlayer: Player,

pub fn Deinit(_: *PlayerAsset, _: *EngineContext) void {}

pub const Name: []const u8 = "PlayerAsset";
