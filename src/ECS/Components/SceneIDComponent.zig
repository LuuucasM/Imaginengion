const ComponentsList = @import("../Components.zig").ComponentsList;
const SceneIDComponent = @This();
pub const ELayerType = enum {
    GameLayer,
    OverlayLayer,
};

ID: u64,
LayerType: ELayerType,



pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == SceneIDComponent) {
            break :blk i;
        }
    }
};
