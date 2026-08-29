const std = @import("std");

const ResolveReq = @import("../Serializer/Serializer.zig").ResolveReq;

const ECSManager = @import("../ECS/ECSManager.zig").ECSManager;

const Entity = @import("../ECSObjects/Entity.zig");
const EntityComponents = @import("../ECSComponents/EComponents.zig");
const EntityComponentsList = EntityComponents.ComponentsList;

pub const ECSManagerE = ECSManager(Entity.Type, &EntityComponentsList);

mECSManagerGO: ECSManagerE = .empty,

mUUIDToWorldID: std.AutoHashMapUnmanaged(u64, usize) = .empty,
mResolveUUIDList: std.ArrayList(ResolveReq) = .empty,
