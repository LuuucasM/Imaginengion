const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const Entity = @import("../../GameObjects/Entity.zig");
const EngineContext = @import("../../Core/EngineContext.zig");
const SpawnPossComponent = @This();

pub const Name: []const u8 = "SpawnPossComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == SpawnPossComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

mEntity: ?Entity,

pub fn Deinit(_: SpawnPossComponent, _: *EngineContext) !void {
    //deinit stuff
}
