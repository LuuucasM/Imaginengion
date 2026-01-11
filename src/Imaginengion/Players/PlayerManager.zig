const std = @import("std");
const ECSManager = @import("../ECS/ECSManager.zig").ECSManager;
const ComponentsList = @import("Components.zig").ComponentsList;
const Player = @import("Player.zig");
const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const PlayerManager = @This();

pub const ECSManagerPlayer = ECSManager(Player.Type, &ComponentsList);

mECSManager: ECSManagerPlayer = .{},

pub fn Init(self: *PlayerManager, engine_allocator: std.mem.Allocator) !void {
    try self.mECSManager.Init(engine_allocator);
}

pub fn Deinit(self: *PlayerManager) !void {
    try self.mECSManager.Deinit();
}

pub fn CreatePlayer(self: *PlayerManager) !Player {
    return Player{
        .mEntityID = try self.mECSManager.CreateEntity(),
        .mECSManagerRef = &self.mECSManager,
    };
}

pub fn DestroyPlayer(self: *PlayerManager, player: Player) void {
    self.mECSManager.DestroyEntity(player.mEntityID);
}

pub fn GetPlayer(self: *PlayerManager, player_id: Player.Type) Player {
    const zone = Tracy.ZoneInit("PlayerManager GetPlayer", @src());
    defer zone.Deinit();
    return Player{ .mEntityID = player_id, .mECSManagerRef = &self.mECSManager };
}

pub fn ProcessDestroyedPlayers(self: *PlayerManager, engine_context: *EngineContext) !void {
    try self.mECSManager.ProcessEvents(engine_context, .EC_RemoveObj);
}

pub fn GetGroup(self: *PlayerManager, frame_allocator: std.mem.Allocator, query: GroupQuery) !std.ArrayList(Player.Type) {
    const zone = Tracy.ZoneInit("PlayerManager GetGroup", @src());
    defer zone.Deinit();
    return try self.mECSManager.GetGroup(frame_allocator, query);
}
