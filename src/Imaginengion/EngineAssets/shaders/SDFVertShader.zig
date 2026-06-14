const std = @import("std");
const gpu = std.gpu;
export fn main() callconv(.spirv_vertex) void {
    const positions = [3]@Vector(2, f32){
        .{ -1.0, -1.0 },
        .{ 3.0, -1.0 },
        .{ -1.0, 3.0 },
    };

    const pos = positions[gpu.vertex_index];
    gpu.position_out.* = .{ pos[0], pos[1], 0.0, 1.0 };
}
