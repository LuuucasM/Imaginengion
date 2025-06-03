const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const Entity = @import("../../GameObjects/Entity.zig");

const ControllerComponent = @This();

mControllingEntity: Entity.Type = Entity.NullEntity,

pub fn Deinit(_: *ControllerComponent) !void {}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == ControllerComponent) {
            break :blk i;
        }
    }
};
