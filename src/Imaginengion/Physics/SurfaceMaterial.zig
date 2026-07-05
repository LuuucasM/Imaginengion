const std = @import("std");
const MathTypes = @import("../Math/MathTypes.zig");

const Vec4 = MathTypes.Vec4;
const Vec3 = MathTypes.Vec3;

pub const SurfaceMaterials = enum {
    Wood,
    //Glass,
    //Steel,
    //Rubber,
    //Ice,
    //Plastic,
};

pub const SurfPhysicsData = struct {
    Restitution: f32,
    StaticFriction: f32,
    KineticFriction: f32,
};

pub const SurfSoundData = struct {
    //nothing yet
};

pub const SurfRenderData = struct {
    //nothing yet
};

pub const SurfMatData = struct {
    PhysicsData: SurfPhysicsData,
    SoundData: SurfSoundData,
    RenderData: SurfRenderData,
};

pub const SurfaceShading = struct {
    Restitution: f32,
    StaticFriction: f32,
    KineticFriction: f32,
};

const SurfaceDatabaseT = std.EnumArray(SurfaceMaterials, SurfMatData);

pub const SurfaceDatabase: SurfaceDatabaseT = .init(.{
    .Wood = @import("SurfaceMaterials/Wood.zig").Data,
});
