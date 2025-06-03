const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const ParentComponent = @This();
const Entity = @import("../../GameObjects/Entity.zig");

mFirstChild: Entity.Type = Entity.NullEntity,

pub fn Deinit(_: *ParentComponent) !void {}

pub fn GetName(self: ParentComponent) []const u8 {
    _ = self;
    return "RelationComponent";
}

pub fn GetInd(self: ParentComponent) u32 {
    _ = self;
    return @intCast(Ind);
}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == ParentComponent) {
            break :blk i;
        }
    }
};
