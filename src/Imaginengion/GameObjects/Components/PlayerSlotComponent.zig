const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const Player = @import("../../Players/Player.zig");
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;

const PlayerSlotComponent = @This();

pub const Category: ComponentCategory = .Unique;
pub const Editable: bool = false;

mPlayerEntity: Player.Type = Player.NullPlayer,

pub fn Deinit(_: *PlayerSlotComponent) !void {}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == PlayerSlotComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

pub fn GetInd(self: PlayerSlotComponent) u32 {
    _ = self;
    return @intCast(Ind);
}

pub fn GetName(_: PlayerSlotComponent) []const u8 {
    return "AISlotComponent";
}
