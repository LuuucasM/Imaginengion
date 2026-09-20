const BuiltinComponentCount = @import("../../ECS/Components.zig").BuiltinComponentCount;
const std = @import("std");
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const StackPosComponent = @This();
const EngineContext = @import("../../Core/EngineContext.zig");

pub const Name: []const u8 = "StackPosComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == StackPosComponent) {
            break :blk i + BuiltinComponentCount;
        }
    }
};

mPosition: usize = std.math.maxInt(usize),

pub fn Deinit(_: *StackPosComponent, _: *EngineContext) void {}
