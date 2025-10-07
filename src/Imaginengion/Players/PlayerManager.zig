const std = @import("std");
const ECSManager = @import("../ECS/ECSManager.zig").ECSManager;
const ComponentsList = @import("Components.zig").ComponentsList;
const Player = @import("Player.zig");
const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;
const Tracy = @import("../Core/Tracy.zig");
const PlayerManager = @This();

pub const ECSManagerPlayer = ECSManager(Player.Type, &ComponentsList);

var StaticPlayerManager: PlayerManager = undefined;

mECSManager: ECSManagerPlayer = undefined,
_PlayersToDestroy: std.ArrayList(Player.Type) = .{},

mEngineAllocator: std.mem.Allocator = undefined,

pub fn Init(engine_allocator: std.mem.Allocator) !void {
    StaticPlayerManager = PlayerManager{
        .mECSManager = try ECSManagerPlayer.Init(engine_allocator),
        .mEngineAllocator = engine_allocator,
    };
}

pub fn Deinit() !void {
    try StaticPlayerManager.mECSManager.Deinit();
    StaticPlayerManager._PlayersToDestroy.deinit(StaticPlayerManager.mEngineAllocator);
}

pub fn CreatePlayer() !Player {
    return Player{
        .mEntityID = try StaticPlayerManager.mECSManager.CreateEntity(),
        .mECSManagerRef = &StaticPlayerManager.mECSManager,
    };
}

pub fn DestroyPlayer(player: Player) void {
    StaticPlayerManager._PlayersToDestroy.append(StaticPlayerManager.mEngineAllocator, player.mEntityID);
}

pub fn GetPlayer(player_id: Player.Type) Player {
    const zone = Tracy.ZoneInit("PlayerManager GetPlayer", @src());
    defer zone.Deinit();
    return Player{ .mEntityID = player_id, .mECSManagerRef = &StaticPlayerManager.mECSManager };
}

pub fn ProcessDestroyedPlayers() !void {
    for (StaticPlayerManager._PlayersToDestroy.items) |player_id| {
        try StaticPlayerManager.mECSManager.DestroyEntity(player_id);
    }
    StaticPlayerManager._PlayersToDestroy.clearAndFree(StaticPlayerManager.mEngineAllocator);
}

pub fn GetGroup(query: GroupQuery, frame_allocator: std.mem.Allocator) !std.ArrayList(Player.Type) {
    const zone = Tracy.ZoneInit("PlayerManager GetGroup", @src());
    defer zone.Deinit();
    return try StaticPlayerManager.mECSManager.GetGroup(query, frame_allocator);
}
