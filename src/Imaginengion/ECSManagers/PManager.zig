const std = @import("std");

const ResolveReq = @import("../Serializer/Serializer.zig").ResolveReq;

const ECSManager = @import("../ECS/ECSManager.zig").ECSManager;

const Player = @import("../ECSObjects/Player.zig");
const PlayerComponents = @import("../ECSComponents/PComponents.zig");

pub const ECSManagerPlayers = ECSManager(Player.Type, &PlayerComponents.ComponentsList);

mECSManagerPL: ECSManagerPlayers = .empty,

mUUIDToWorldID: std.AutoHashMapUnmanaged(u64, usize) = .empty,
mResolveUUIDList: std.ArrayList(ResolveReq) = .empty,
