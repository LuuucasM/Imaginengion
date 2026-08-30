const std = @import("std");

const ResolveReq = @import("../Serializer/Serializer.zig").ResolveReq;

const ECSManager = @import("../ECS/ECSManager.zig").ECSManager;

const GameContext = @import("../ECSObjects/GameContext.zig");
const GameModeComponentsList = @import("../ECSComponents/GCComponents.zig").ComponentsList;

pub const ECSManagerGC = ECSManager(GameContext.Type, &GameModeComponentsList);

mECSManagerSC: ECSManagerGC = .empty,

mUUIDToWorldID: std.AutoHashMapUnmanaged(u64, usize) = .empty,
mResolveUUIDList: std.ArrayList(ResolveReq) = .empty,

pub fn CreateGameMode(self: *SceneManager, engine_context: *EngineContext, config: GameContext.NewGameModeConfig) !GameContext {
    var new_game_mode = GameMode{ .mEntityID = try self.mECSManagerGM.CreateEntity(engine_context.EngineAllocator()), .mScenemanager = self };
    try new_game_mode.CreateGameModeConfig(engine_context, config);
    return new_game_mode;
}
pub fn GetGameModeGroup(self: *const SceneManager, frame_allocator: std.mem.Allocator, comptime query: GroupQuery) !std.ArrayList(GameContext.Type) {
    return try self.mECSManagerGM.GetGroup(frame_allocator, query);
}
pub fn GameECSCallback(scene_manager: *anyopaque, engine_context: *EngineContext, event: ECSManagerGameContexts.ECSEventManager.EventType) anyerror!bool {
    _ = scene_manager;
    _ = engine_context;
    _ = event;
    return true;
}
