const std = @import("std");
const ECSManager = @import("../ECS/ECSManager.zig").ECSManager;
const ComponentsList = @import("Components.zig").ComponentsList;
const Player = @import("Player.zig");
const PlayerManager = @This();

pub const ECSManagerPlayer = ECSManager(Player.Type, ComponentsList.len);

var StaticPlayerManager: PlayerManager = undefined;

mECSManager: ECSManagerPlayer = undefined,

pub fn Init(engine_allocator: std.mem.Allocator) !void {
    StaticPlayerManager = PlayerManager{
        .mECSManager = try ECSManager(Player.Type, ComponentsList.len).Init(engine_allocator, ComponentsList),
    };
}

pub fn CreatePlayer() !Player {
    return Player{
        .mEntityID = try StaticPlayerManager.mECSManager.CreateEntity(),
        .mECSManagerRef = &StaticPlayerManager.mECSManager,
    };
}

pub fn Deinit() !void {
    StaticPlayerManager.mECSManager.Deinit();
}
