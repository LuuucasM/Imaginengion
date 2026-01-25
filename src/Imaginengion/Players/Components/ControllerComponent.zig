const Entity = @import("../../GameObjects/Entity.zig");
const ComponentsList = @import("../Components.zig").ComponentsList;
const ControllerComponent = @This();

mControlledEntityID: Entity.Type = Entity.NullEntity,

pub fn Deinit(_: *ControllerComponent) !void {}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == ControllerComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

pub const Editable: bool = false;
