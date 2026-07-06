const std = @import("std");
const SurfMat = @import("SurfaceMaterial.zig");
const MedMat = @import("MediumMaterial.zig");

pub const MaterialData = union(enum) {
    Surface: struct {
        Kind: SurfMat.SurfaceMaterials,
        Scale: SurfMat.SurfMatData, // reused type, values act as multipliers
    },
    Medium: struct {
        Kind: MedMat.MediumMaterials,
        Scale: MedMat.MedMatData,
    },
};

pub const BodyMaterial = struct {
    Data: MaterialData,

    pub fn Physics(self: BodyMaterial) union(enum) {
        Surface: SurfMat.SurfPhysicsData,
        Medium: MedMat.MedPhysicsData,
    } {
        return switch (self.Data) {
            .Surface => |s| .{ .Surface = SurfMat.SurfaceDatabase.get(s.Kind).PhysicsData },
            .Medium => |m| .{ .Medium = MedMat.MediumDatabase.get(m.Kind).PhysicsData },
        };
    }

    pub fn Sound(self: BodyMaterial) union(enum) {
        Surface: SurfMat.SurfSoundData,
        Medium: MedMat.MedSoundData,
    } {
        return switch (self.Data) {
            .Surface => |s| .{ .Surface = SurfMat.SurfaceDatabase.get(s.Kind).SoundData },
            .Medium => |m| .{ .Medium = MedMat.MediumDatabase.get(m.Kind).SoundData },
        };
    }

    pub fn Render(self: BodyMaterial) union(enum) {
        Surface: SurfMat.SurfRenderData,
        Medium: MedMat.MedRenderData,
    } {
        return switch (self.Data) {
            .Surface => |s| .{ .Surface = SurfMat.SurfaceDatabase.get(s.Kind).RenderData },
            .Medium => |m| .{ .Medium = MedMat.MediumDatabase.get(m.Kind).RenderData },
        };
    }

    pub fn ScaledPhysics(self: BodyMaterial) union(enum) {
        Surface: SurfMat.SurfPhysicsData,
        Medium: MedMat.MedPhysicsData,
    } {
        return switch (self.Data) {
            .Surface => |s| blk: {
                const base = SurfMat.SurfaceDatabase.get(s.Kind).PhysicsData;
                const scale = s.Scale.PhysicsData;
                break :blk .{ .Surface = .{
                    .Restitution = base.Restitution * scale.Restitution,
                    .StaticFriction = base.StaticFriction * scale.StaticFriction,
                    .KineticFriction = base.KineticFriction * scale.KineticFriction,
                } };
            },
            .Medium => |m| .{ .Medium = MedMat.MediumDatabase.get(m.Kind).PhysicsData }, //nothing yet
        };
    }

    pub fn ScaledSound(self: BodyMaterial) union(enum) {
        Surface: SurfMat.SurfSoundData,
        Medium: MedMat.MedSoundData,
    } {
        return switch (self.Data) {
            .Surface => |s| .{ .Surface = SurfMat.SurfaceDatabase.get(s.Kind).SoundData }, // nothing yet
            .Medium => |m| .{ .Medium = MedMat.MediumDatabase.get(m.Kind).SoundData }, // nothing yet
        };
    }

    pub fn ScaledRender(self: BodyMaterial) union(enum) {
        Surface: SurfMat.SurfRenderData,
        Medium: MedMat.MedRenderData,
    } {
        return switch (self.Data) {
            .Surface => |s| .{ .Surface = SurfMat.SurfaceDatabase.get(s.Kind).RenderData }, // nothing yet
            .Medium => |m| blk: {
                const base = MedMat.MediumDatabase.get(m.Kind).RenderData;
                const scl = m.Scale.RenderData;
                break :blk .{ .Medium = .{
                    .Absorption = base.Absorption * scl.Absorption,
                    .Scattering = base.Scattering * scl.Scattering,
                } };
            },
        };
    }
};
