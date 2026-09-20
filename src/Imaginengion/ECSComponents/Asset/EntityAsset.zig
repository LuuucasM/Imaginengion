const std = @import("std");
const EntityAsset = @This();
const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");

pub const empty: EntityAsset = .{
    .mEntity = .empty,
};

mEntity: Entity,

pub fn Deinit(_: *EntityAsset, _: *EngineContext) void {}

pub const Name: []const u8 = "EntityAsset";
