const std = @import("std");
const ComponentsList = @import("../AComponents.zig").ComponentsList;
const EntityAsset = @This();
const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");

pub const empty: EntityAsset = .{
    .mEntity = .empty,
};

mEntity: Entity,

pub fn Deinit(_: *EntityAsset, _: *EngineContext) !void {}

pub const Name: []const u8 = "EntityAsset";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |asset_type, i| {
        if (asset_type == EntityAsset) {
            break :blk i + 5;
        }
    }
};
