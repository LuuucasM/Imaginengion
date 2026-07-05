const std = @import("std");

const MathTypes = @import("../Math/MathTypes.zig");

const Vec3 = MathTypes.Vec3;

pub const MediumMaterials = enum {
    Air,
    //Water,
    //Vacuum,
    //Fog,
    //Smoke,
};

pub const MedPhysicsData = struct {
    //nothing yet
};

pub const MedSoundData = struct {
    //nothing yet
};

pub const MedRenderData = struct {
    Absorption: Vec3(f32),
    Scattering: Vec3(f32),
};

pub const MedMatData = struct {
    PhysicsData: MedPhysicsData,
    SoundData: MedSoundData,
    RenderData: MedRenderData,
};

pub const MediumShading = struct {
    Absorption: Vec3(f32).VectorT,
    Scattering: Vec3(f32).VectorT,
};

const MediumDatabaseT = std.EnumArray(MediumMaterials, MedMatData);

pub const MediumDatabase: MediumDatabaseT = .init(.{
    .Air = @import("MediumMaterials/Air.zig").Data,
});
