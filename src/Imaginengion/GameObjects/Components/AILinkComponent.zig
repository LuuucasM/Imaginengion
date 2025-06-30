const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const Entity = @import("../../GameObjects/Entity.zig");

const AILinkComponent = @This();

mAIEntity: Entity.Type = Entity.NullEntity,

pub fn Deinit(_: *AILinkComponent) !void {}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == AILinkComponent) {
            break :blk i;
        }
    }
};
