const MedMatData = @import("../MediumMaterial.zig").MedMatData;

pub const Data: MedMatData = .{
    .PhysicsData = .{},
    .SoundData = .{},
    .RenderData = .{
        .Absorption = .{ .x = 0, .y = 0, .z = 0 },
        .Scattering = .{ .x = 0.000002, .y = 0.00001, .z = 0.00004 },
    },
};
