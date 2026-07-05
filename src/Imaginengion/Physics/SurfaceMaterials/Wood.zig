const SurfMatData = @import("../SurfaceMaterial.zig").SurfMatData;

const Data: SurfMatData = .{
    .PhysicsData = .{
        .Restitution = 0.4,
        .StaticFriction = 0.5,
        .KineticFriction = 0.35,
    },
    .RenderData = .{},
    .SoundData = .{},
};
