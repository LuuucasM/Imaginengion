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

mEngineAllocator: std.mem.Allocator = undefined,

pub fn Init(engine_allocator: std.mem.Allocator) !void {
    StaticPlayerManager = PlayerManager{
        .mECSManager = try ECSManagerPlayer.Init(engine_allocator),
        .mEngineAllocator = engine_allocator,
    };
}

pub fn Deinit() !void {
    try StaticPlayerManager.mECSManager.Deinit();
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
    const zone = Tracy.ZoneInit("PlayerManager GetPlayer", @src());
    defer zone.Deinit();
    return Player{ .mEntityID = player_id, .mECSManagerRef = &StaticPlayerManager.mECSManager };
}

pub fn ProcessDestroyedPlayers() !void {
    try StaticPlayerManager.mECSManager.ProcessEvents(.EC_RemoveObj);
}

pub fn GetGroup(query: GroupQuery, frame_allocator: std.mem.Allocator) !std.ArrayList(Player.Type) {
    const zone = Tracy.ZoneInit("PlayerManager GetGroup", @src());
    defer zone.Deinit();
    return try StaticPlayerManager.mECSManager.GetGroup(query, frame_allocator);
}
