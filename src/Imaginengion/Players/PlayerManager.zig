const std = @import("std");
const ECSManager = @import("../ECS/ECSManager.zig").ECSManager;
const ComponentsList = @import("Components.zig").ComponentsList;
const Player = @import("Player.zig");
const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;
const PlayerManager = @This();

pub const ECSManagerPlayer = ECSManager(Player.Type, ComponentsList.len);

var StaticPlayerManager: PlayerManager = undefined;

mECSManager: ECSManagerPlayer = undefined,

pub fn Init(engine_allocator: std.mem.Allocator) !void {
    StaticPlayerManager = PlayerManager{
        .mECSManager = try ECSManager(Player.Type, ComponentsList.len).Init(engine_allocator, ComponentsList),
    };
}

pub fn Deinit() !void {
    StaticPlayerManager.mECSManager.Deinit();
}

pub fn CreatePlayer() !Player {
    return Player{
        .mEntityID = try StaticPlayerManager.mECSManager.CreateEntity(),
        .mECSManagerRef = &StaticPlayerManager.mECSManager,
    };
}

pub fn DestroyPlayer(player: Player) void {
    StaticPlayerManager.mECSManager.DestroyEntity(player.mEntityID);
}

pub fn GetPlayer(player_id: Player.Type) Player {
    return Player{ .mEntityID = player_id, .mECSManagerRef = &StaticPlayerManager.mECSManager };
}

pub fn ProcessDestroyedPlayers() void {
    StaticPlayerManager.mECSManager.ProcessDestroyedEntities();
}

pub fn GetGroup(query: GroupQuery, frame_allocator: std.mem.Allocator) !std.ArrayList(Player.Type) {
    return try StaticPlayerManager.mECSManager.GetGroup(query, frame_allocator);
}
