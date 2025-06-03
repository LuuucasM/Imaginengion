const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const EntityType = @import("../Entity.zig").Type;
const PlayerComponent = @This();

mToControlEntity: EntityType,

pub fn Deinit(_: *PlayerComponent) !void {}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == PlayerComponent) {
            break :blk i;
        }
    }
};
