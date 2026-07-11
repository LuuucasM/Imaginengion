const std = @import("std");
const MathTypes = @import("../Math/MathTypes.zig");
const ImguiManager = @import("../Imgui/Imgui.zig");

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

    pub fn ImguiRender(self: SurfPhysicsData, label: []const u8) void {
        ImguiManager.ImguiSeparator();
        ImguiManager.RenderText(label);
        ImguiManager.RenderFloatInput(&self.Restitution, "Restitution", 0.01, 0.1);
        ImguiManager.RenderFloatInput(&self.StaticFriction, "Static Friction", 0.01, 0.1);
        ImguiManager.RenderFloatInput(&self.KineticFriction, "Kinetic Friction", 0.01, 0.1);
    }
};

pub const SurfSoundData = struct {
    //nothing yet
};

pub const SurfRenderData = struct {
    //nothing yet
    pub fn ImguiRender(self: SurfRenderData, label: []const u8) void {
        _ = self;
        ImguiManager.ImguiSeparator();
        ImguiManager.RenderText(label);
    }
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
