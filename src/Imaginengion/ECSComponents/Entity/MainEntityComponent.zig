const ComponentsList = @import("../Components.zig").ComponentsList;
const EngineContext = @import("../../Core/EngineContext.zig");

const MainEntityComp = @This();

pub const Editable: bool = false;
pub const Name: []const u8 = "MainEntityComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == MainEntityComp) {
            break :blk i + 5; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

pub fn Deinit(_: *MainEntityComp, _: *EngineContext) !void {}
