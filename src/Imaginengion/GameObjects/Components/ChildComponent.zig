const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const ChildComponent = @This();

const Entity = @import("../../GameObjects/Entity.zig");
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;

mFirst: Entity.Type = Entity.NullEntity,
mPrev: Entity.Type = Entity.NullEntity,
mNext: Entity.Type = Entity.NullEntity,
mParent: Entity.Type = Entity.NullEntity,

pub const Category: ComponentCategory = .Unique;

pub fn Deinit(_: *ChildComponent) !void {}

pub fn GetName(self: ChildComponent) []const u8 {
    _ = self;
    return "ChildComponent";
}

pub fn GetInd(self: ChildComponent) u32 {
    _ = self;
    return @intCast(Ind);
}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == ChildComponent) {
            break :blk i;
        }
    }
};
