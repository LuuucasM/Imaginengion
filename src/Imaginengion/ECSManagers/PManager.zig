const std = @import("std");

const ResolveReq = @import("../Serializer/Serializer.zig").ResolveReq;

const ECSManager = @import("../ECS/ECSManager.zig").ECSManager;

const Player = @import("../ECSObjects/Player.zig");
const PlayerComponents = @import("../ECSComponents/PComponents.zig");

pub const ECSManagerPlayers = ECSManager(Player.Type, &PlayerComponents.ComponentsList);

mECSManagerPL: ECSManagerPlayers = .empty,

mUUIDToWorldID: std.AutoHashMapUnmanaged(u64, usize) = .empty,
mResolveUUIDList: std.ArrayList(ResolveReq) = .empty,

pub fn CreatePlayer(self: *SceneManager, engine_context: *EngineContext, new_player_config: Player.NewPlayerConfig) !Player {
    var new_player = Player{ .mEntityID = try self.mECSManagerPL.CreateEntity(engine_context.EngineAllocator()), .mScenemanager = self };
    try new_player.CreatePlayerConfig(engine_context, new_player_config);
    return new_player;
}
pub fn GetPlayer(self: *SceneManager, player_id: Player.Type) Player {
    return Player{ .mEntityID = player_id, .mScenemanager = self };
}
pub fn GetPlayerGroup(self: *SceneManager, frame_allocator: std.mem.Allocator, query: GroupQuery) !std.ArrayList(Player.Type) {
    const zone = Tracy.ZoneInit("SceneManager::GetPlayerGroup", @src());
    defer zone.Deinit();
    return try self.mECSManagerPL.GetGroup(frame_allocator, query);
}
pub fn PlayerECSCallback(scene_manager: *anyopaque, engine_context: *EngineContext, event: ECSManagerPlayers.ECSEventManager.EventType) anyerror!bool {
    const self: *SceneManager = @ptrCast(@alignCast(scene_manager));
    _ = self;
    _ = engine_context;
    _ = event;
    return true;
}
