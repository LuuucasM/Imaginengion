const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const Player = @import("../../Players/Player.zig");

const PlayerSlotComponent = @This();

mPlayerEntity: Player.Type = Player.NullPlayer,

pub fn Deinit(_: *PlayerSlotComponent) !void {}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == PlayerSlotComponent) {
            break :blk i;
        }
    }
};
