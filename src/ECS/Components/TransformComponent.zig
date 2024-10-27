const ComponentsList = @import("../Components.zig").ComponentsList;
const TransformComponent = @This();
const LinAlg = @import("../../Math/LinAlg.zig");

Position: LinAlg.Vec3f32,
Rotation: LinAlg.Quatf32,
Scale: LinAlg.Vec3f32,

TransformMatrix: LinAlg.Mat4f32,
Dirty: bool,

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == TransformComponent) {
            break :blk i;
        }
    }
};

pub fn ImguiRender(self: *TransformComponent) void {

}