const ComponentsList = @import("../SceneComponents.zig").ComponentsList;

//scripts
pub const OnSceneStartScript = struct {
    pub const RunFuncSig = false; //TODO
    bit: u1 = 0,
    pub const Ind: usize = blk: {
        for (ComponentsList, 0..) |component_type, i| {
            if (component_type == OnSceneStartScript) {
                break :blk i;
            }
        }
    };
};
