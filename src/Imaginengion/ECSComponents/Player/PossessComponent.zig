const BuiltinComponentCount = @import("../../ECS/Components.zig").BuiltinComponentCount;
const Entity = @import("../../GameObjects/Entity.zig");
const ComponentsList = @import("../Components.zig").ComponentsList;
const EngineContext = @import("../../Core/EngineContext.zig");
const PossessComponent = @This();

pub const Name: []const u8 = "PossessComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == PossessComponent) {
            break :blk i + BuiltinComponentCount;
        }
    }
};

mPossessedEntity: Entity = .{},

pub fn Deinit(_: *PossessComponent, _: *EngineContext) !void {}
