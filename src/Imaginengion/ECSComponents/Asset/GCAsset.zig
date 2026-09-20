const std = @import("std");
const GCAsset = @This();
const EngineContext = @import("../../Core/EngineContext.zig");
const GameContext = @import("../../ECSObjects/GameContext.zig");

pub const empty: GCAsset = .{
    .mGameContext = .empty,
};

mGameContext: GameContext,

pub fn Deinit(_: *GCAsset, _: *EngineContext) void {}

pub const Name: []const u8 = "GCAsset";
