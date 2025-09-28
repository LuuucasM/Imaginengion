const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const IDComponent = @This();
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;

pub const Category: ComponentCategory = .Unique;
pub const Editable: bool = false;

SceneID: u128 = std.math.maxInt(u128),

pub fn Deinit(_: *IDComponent) !void {}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == IDComponent) {
            break :blk i;
        }
    }
};
