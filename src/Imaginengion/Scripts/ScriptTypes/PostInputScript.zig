const ComponentsList = @import("../ScriptTypes.zig").ComponentsList;
const PostInputScript = @This();

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == PostInputScript) {
            break :blk i;
        }
    }
};
