const std = @import("std");

const ResolveReq = @import("../Serializer/Serializer.zig").ResolveReq;

const ECSManager = @import("../ECS/ECSManager.zig").ECSManager;

const GameContext = @import("../ECSObjects/GameContext.zig");
const GameModeComponentsList = @import("../ECSComponents/GCComponents.zig").ComponentsList;

pub const ECSManagerGC = ECSManager(GameContext.Type, &GameModeComponentsList);

mECSManagerSC: ECSManagerGC = .empty,

mUUIDToWorldID: std.AutoHashMapUnmanaged(u64, usize) = .empty,
mResolveUUIDList: std.ArrayList(ResolveReq) = .empty,
