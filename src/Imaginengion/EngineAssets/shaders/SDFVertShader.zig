const std = @import("std");
const spirv = std.spirv;
export fn main() callconv(.spirv_vertex) void {
    const positions = [3]@Vector(2, f32){
        .{ -1.0, -1.0 },
        .{ 3.0, -1.0 },
        .{ -1.0, 3.0 },
    };

    const pos = positions[spirv.vertex_index];
    spirv.position_out.* = .{ pos[0], pos[1], 0.0, 1.0 };
}
