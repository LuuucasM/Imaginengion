const ComponentsList = @import("../Components.zig").ComponentsList;

//scripts
pub const OnInputPressedScript = struct {
    bit: u1 = 0,
    pub const Ind: usize = blk: {
        for (ComponentsList, 0..) |component_type, i| {
            if (component_type == OnInputPressedScript) {
                break :blk i;
            }
        }
    };
};

pub const OnUpdateInputScript = struct {
    bit: u1 = 0,
    pub const Ind: usize = blk: {
        for (ComponentsList, 0..) |component_type, i| {
            if (component_type == OnUpdateInputScript) {
                break :blk i;
            }
        }
    };
};

pub const PrimaryCameraTag = struct {
    bit: u1 = 0,
    pub const Ind: usize = blk: {
        for (ComponentsList, 0..) |component_type, i| {
            if (component_type == PrimaryCameraTag) {
                break :blk i;
            }
        }
    };
};

pub const EditorCameraTag = struct {
    bit: u1 = 0,
    pub const Ind: usize = blk: {
        for (ComponentsList, 0..) |component_type, i| {
            if (component_type == EditorCameraTag) {
                break :blk i;
            }
        }
    };
};
