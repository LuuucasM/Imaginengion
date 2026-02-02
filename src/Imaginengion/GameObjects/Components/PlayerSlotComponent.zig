const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const Player = @import("../../Players/Player.zig");
const EngineContext = @import("../../Core/EngineContext.zig");

const PlayerSlotComponent = @This();

pub const Editable: bool = false;
pub const Name: []const u8 = "PlayerSlotComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == PlayerSlotComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

mPlayerEntity: ?Player = null,

pub fn Deinit(_: *PlayerSlotComponent, _: *EngineContext) !void {}
