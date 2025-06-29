const Entity = @import("../../GameObjects/Entity.zig");
const ComponentsList = @import("../Components.zig").ComponentsList;
const ControllerComponent = @This();

mControlledEntityID: Entity.Type,

pub fn Deinit(_: *ControllerComponent) !void {}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == ControllerComponent) {
            break :blk i;
        }
    }
};
