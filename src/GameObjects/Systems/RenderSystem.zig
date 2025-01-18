const SystemsList = @import("../Systems.zig").SystemsList;
const RenderSystem = @This();

pub const Ind: usize = blk: {
    for (SystemsList, 0..) |system_type, i| {
        if (system_type == RenderSystem) {
            break :blk i;
        }
    }
};
