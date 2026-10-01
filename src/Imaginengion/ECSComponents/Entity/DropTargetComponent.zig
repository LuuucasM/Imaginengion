const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig");
const DropTargetComponent = @This();

pub const Editable: bool = false;
pub const Name: []const u8 = "DropTargetComponent";

/// Makes an entity somewhere a drag source (DragSourceComponent) can be dropped: one that has any of these
/// components. Each is a component's slot in the entity ECS (ComponentInd), which is how a type can be kept in a
/// component; make the list with Accepting. Empty takes nothing. Set up by code, never saved: slots change whenever
/// the component list does
mAccepts: []const usize = &.{},

pub fn Deinit(_: *DropTargetComponent, _: *EngineContext) void {}

/// A drop target taking drag sources that have any of `component_types`, e.g. Accepting(&.{ ItemComponent })
pub fn Accepting(comptime component_types: []const type) DropTargetComponent {
    const ComponentInd = @import("../../ECSManagers/EManager.zig").ECSManagerT.ComponentInd;
    const slots = comptime blk: {
        var list: [component_types.len]usize = undefined;
        for (component_types, 0..) |component_type, i| list[i] = ComponentInd(component_type);
        break :blk list;
    };
    return .{ .mAccepts = &slots };
}
