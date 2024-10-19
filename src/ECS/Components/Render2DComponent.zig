const ComponentsList = @import("../Components.zig").ComponentsList;
const Render2DComponent = @This();
const Vec4f32 = @import("../../Math/LinAlg.zig").Vec4f32;

Texture: u64,
Color: Vec4f32 = .{ 1.0, 1.0, 1.0, 1.0 },
TilingFactor: f32 = 1.0,


pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == Render2DComponent) {
            break :blk i;
        }
    }
};
