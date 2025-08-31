const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const Player = @import("../../Players/Player.zig");
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;

const PlayerSlotComponent = @This();

pub const Category: ComponentCategory = .Unique;

mPlayerEntity: Player.Type = Player.NullPlayer,

pub fn Deinit(_: *PlayerSlotComponent) !void {}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == PlayerSlotComponent) {
            break :blk i;
        }
    }
};
