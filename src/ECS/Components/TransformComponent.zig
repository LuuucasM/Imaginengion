const ComponentsList = @import("../Components.zig").ComponentsList;
const TransformComponent = @This();
const LinAlg = @import("../../Math/LinAlg.zig");

Transform: LinAlg.Mat4f32 = LinAlg.InitMat4CompTime(1.0),



pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == TransformComponent) {
            break :blk i;
        }
    }
};
