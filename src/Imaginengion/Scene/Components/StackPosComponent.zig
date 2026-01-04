const std = @import("std");
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const StackPosComponent = @This();
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;
const EngineContext = @import("../../Core/EngineContext.zig");

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == StackPosComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

pub const Category: ComponentCategory = .Unique;

mPosition: usize = std.math.maxInt(usize),

pub fn Deinit(_: *StackPosComponent, _: *EngineContext) !void {}
