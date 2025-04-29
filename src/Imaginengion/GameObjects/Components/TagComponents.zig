const ComponentsList = @import("../Components.zig").ComponentsList;

//scripts
pub const OnKeyPressedScript = struct {
    bit: u1 = 0,
    pub const Ind: usize = blk: {
        for (ComponentsList, 0..) |component_type, i| {
            if (component_type == OnKeyPressedScript) {
                break :blk i;
            }
        }
    };
};
