const std = @import("std");
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const StackPosComponent = @This();
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == StackPosComponent) {
            break :blk i;
        }
    }
};

pub const Category: ComponentCategory = .Unique;

mPosition: usize = std.math.maxInt(usize),

pub fn Deinit(_: *StackPosComponent) !void {}
