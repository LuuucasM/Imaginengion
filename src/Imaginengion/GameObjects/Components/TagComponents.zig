const ComponentsList = @import("../Components.zig").ComponentsList;

//scripts
pub const OnKeyPressedScriptTag = struct {
    bit: u1 = 0,
    pub const Ind: usize = blk: {
        for (ComponentsList, 0..) |component_type, i| {
            if (component_type == OnKeyPressedScriptTag) {
                break :blk i;
            }
        }
    };
};
