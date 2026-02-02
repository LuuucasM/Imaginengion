const Entity = @import("../../GameObjects/Entity.zig");
const ComponentsList = @import("../Components.zig").ComponentsList;
const PossessComponent = @This();

pub const Name: []const u8 = "PossessComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == PossessComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

mPossessedEntity: ?Entity = null,

pub fn Deinit(_: *PossessComponent) !void {}
