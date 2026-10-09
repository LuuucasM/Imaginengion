const std = @import("std");
const Inspector = @import("../UI/Inspector.zig");
const MathTypes = @import("../Math/MathTypes.zig");

const Vec4 = MathTypes.Vec4;
const Vec3 = MathTypes.Vec3;

pub const SurfaceMaterials = enum {
    Custom,
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

    pub fn UIRender(self: *SurfPhysicsData, ui: *Inspector.Builder) !void {
        try ui.Float(&self.Restitution, "Restitution", .{ .Speed = 0.01 });
        try ui.Float(&self.StaticFriction, "Static Friction", .{ .Speed = 0.01 });
        try ui.Float(&self.KineticFriction, "Kinetic Friction", .{ .Speed = 0.01 });
    }
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

pub const SurfaceScaleIdentity: SurfMatData = .{
    .PhysicsData = .{
        .Restitution = 1.0,
        .StaticFriction = 1.0,
        .KineticFriction = 1.0,
    },
    .SoundData = .{},
    .RenderData = .{},
};

const SurfaceDatabaseT = std.EnumArray(SurfaceMaterials, SurfMatData);

pub const SurfaceDatabase: SurfaceDatabaseT = .init(.{
    .Custom = SurfaceScaleIdentity,
    .Wood = @import("SurfaceMaterials/Wood.zig").Data,
});
