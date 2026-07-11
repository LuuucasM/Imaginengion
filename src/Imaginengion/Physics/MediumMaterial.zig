const std = @import("std");
const ImguiManager = @import("../Imgui/Imgui.zig");
const MathTypes = @import("../Math/MathTypes.zig");

const Vec3 = MathTypes.Vec3;

pub const MediumMaterials = enum {
    Custom,
    Air,
    //Water,
    //Vacuum,
    //Fog,
    //Smoke,
};

pub const MedPhysicsData = struct {
    //nothing yet

    pub fn ImguiRender(self: MedPhysicsData, label: []const u8) void {
        _ = self;
        ImguiManager.ImguiSeparator();
        ImguiManager.RenderText(label);
    }
};

pub const MedSoundData = struct {
    //nothing yet
};

pub const MedRenderData = struct {
    Absorption: Vec3(f32),
    Scattering: Vec3(f32),

    pub fn ImguiRender(self: MedRenderData, label: []const u8) void {
        ImguiManager.ImguiSeparator();
        ImguiManager.RenderText(label);
        ImguiManager.RenderVec3(&self.Absorption, "Absorbtion", 0.0, 0.01, 100);
        ImguiManager.RenderVec3(&self.Scattering, "Scattering", 0, 0.01, 100);
    }
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

pub const MediumScaleIdentity: MedMatData = .{
    .PhysicsData = .{},
    .SoundData = .{},
    .RenderData = .{
        .Absorption = .{ 1.0, 1.0, 1.0 },
        .Scattering = .{ 1.0, 1.0, 1.0 },
    },
};

const MediumDatabaseT = std.EnumArray(MediumMaterials, MedMatData);

pub const MediumDatabase: MediumDatabaseT = .init(.{
    .Custom = MediumScaleIdentity,
    .Air = @import("MediumMaterials/Air.zig").Data,
});
