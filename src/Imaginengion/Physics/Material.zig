const std = @import("std");
const SurfMat = @import("SurfaceMaterial.zig");
const MedMat = @import("MediumMaterial.zig");
const ImguiManager = @import("../Imgui/Imgui.zig");

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

pub const PhysicsMaterial = union(enum) {
    Surface: struct {
        Kind: SurfMat.SurfaceMaterials,
        Scale: SurfMat.SurfPhysicsData,
    },
    Medium: struct {
        Kind: MedMat.MediumMaterials,
        Scale: MedMat.MedPhysicsData,
    },

    pub const default: PhysicsMaterial = .{ .Surface = .{
        .Kind = .Wood,
        .Scale = SurfMat.SurfaceScaleIdentity,
    } };

    pub fn GetMaterialData(self: PhysicsMaterial) union(enum) {
        Surface: SurfMat.SurfPhysicsData,
        Medium: MedMat.MedPhysicsData,
    } {
        return switch (self) {
            .Surface => |s| .{ .Surface = SurfMat.SurfaceDatabase.get(s.Kind).PhysicsData },
            .Medium => |m| .{ .Medium = MedMat.MediumDatabase.get(m.Kind).PhysicsData },
        };
    }

    pub fn GetScaleData(self: PhysicsMaterial) union(enum) {
        Surface: SurfMat.SurfPhysicsData,
        Medium: MedMat.MedPhysicsData,
    } {
        return switch (self) {
            .Surface => |s| .{ .Surface = s.Scale },
            .Medium => |m| .{ .Medium = m.Scale },
        };
    }

    pub fn GetScaledMaterial(self: PhysicsMaterial) union(enum) {
        Surface: SurfMat.SurfPhysicsData,
        Medium: MedMat.MedPhysicsData,
    } {
        return switch (self) {
            .Surface => |s| blk: {
                const base = SurfMat.SurfaceDatabase.get(s.Kind).PhysicsData;
                const scale = s.Scale;

                break :blk .{ .Surface = .{
                    .Restitution = base.Restitution * scale.Restitution,
                    .StaticFriction = base.StaticFriction * scale.StaticFriction,
                    .KineticFriction = base.KineticFriction * scale.KineticFriction,
                } };
            },
            .Medium => |m| blk: {
                //NOTE: there is nothing for this now but will need to uncomment when there is
                _ = m;
                //const base = MedMat.MediumDatabase.get(m.Kind).PhysicsData;
                //const scale = m.Scale;

                break :blk .{ .Medium = .{} };
            },
        };
    }

    pub fn ImguiRender(self: PhysicsMaterial) void {
        switch (self) {
            .Surface => |s| {
                ImguiManager.RenderEnum(SurfMat.SurfaceMaterials, &s.Kind, "Surface Material");
                s.Scale.ImguiRender("Scale");
            },
            .Medium => |m| {
                ImguiManager.RenderEnum(MedMat.MediumMaterials, &m.Kind, "Medium Material");
                m.Scale.ImguiRender("Scale");
            },
        }
    }
};

pub const SurfaceRenderMat = struct {
    Kind: SurfMat.SurfaceMaterials,
    Scale: SurfMat.SurfRenderData,

    pub const default: SurfaceRenderMat = .{
        .Kind = .Wood,
        .Scale = SurfMat.SurfaceScaleIdentity.RenderData,
    };

    pub fn ImguiRender(self: SurfaceRenderMat) void {
        ImguiManager.RenderEnum(SurfMat.SurfaceMaterials, &self.Kind, "Surface Material");
        self.Scale.ImguiRender("Scale");
    }

    pub fn GetMaterialData(self: SurfaceRenderMat) SurfMat.SurfRenderData {
        SurfMat.SurfaceDatabase.get(self.Kind).RenderData;
    }

    pub fn GetScaleData(self: SurfaceRenderMat) SurfMat.SurfRenderData {
        return self.Scale;
    }

    pub fn GetScaledMaterial(self: SurfaceRenderMat) SurfMat.SurfRenderData {
        _ = self;
        return .{};
    }
};

pub const MediumRenderMat = struct {
    Kind: MedMat.MediumMaterials,
    Scale: MedMat.MedRenderData,

    pub const default: MediumRenderMat = .{
        .Kind = .Wood,
        .Scale = MedMat.MediumScaleIdentity.RenderData,
    };

    pub fn ImguiRender(self: MediumRenderMat) void {
        ImguiManager.RenderEnum(MedMat.MediumMaterials, &self.Kind, "Medium Material");
        self.Scale.ImguiRender("Scale");
    }
};

pub const RenderMaterial = union(enum) {
    Surface: SurfaceRenderMat,
    Medium: MediumRenderMat,

    pub const default: RenderMaterial = .{
        .Surface = .default,
    };

    pub fn GetMaterialData(self: RenderMaterial) union(enum) {
        Surface: SurfMat.SurfRenderData,
        Medium: MedMat.MedRenderData,
    } {
        return switch (self) {
            .Surface => |s| .{ .Surface = SurfMat.SurfaceDatabase.get(s.Kind).RenderData },
            .Medium => |m| .{ .Medium = MedMat.MediumDatabase.get(m.Kind).RenderData },
        };
    }

    pub fn GetScaleData(self: RenderMaterial) union(enum) {
        Surface: SurfMat.SurfRenderData,
        Medium: MedMat.MedRenderData,
    } {
        return switch (self) {
            .Surface => |s| .{ .Surface = s.Scale },
            .Medium => |m| .{ .Medium = m.Scale },
        };
    }

    pub fn GetScaledMaterial(self: RenderMaterial) union(enum) {
        Surface: SurfMat.SurfRenderData,
        Medium: MedMat.MedRenderData,
    } {
        return switch (self) {
            .Surface => |s| blk: {
                _ = s;
                //const base = SurfMat.SurfaceDatabase.get(s.Kind).RenderData;
                //const scale = s.Scale;

                break :blk .{ .Surface = .{} };
            },
            .Medium => |m| blk: {
                const base = MedMat.MediumDatabase.get(m.Kind).RenderData;
                const scale = m.Scale;

                break :blk .{ .Medium = .{
                    .Absorption = base.Absorption.MulVec(scale.Absorption),
                    .Scattering = base.Scattering.MulVec(scale.Scattering),
                } };
            },
        };
    }

    pub fn ImguiRender(self: RenderMaterial) void {
        switch (self) {
            .Surface => |s| s.ImguiRender(),
            .Medium => |m| m.ImguiRender(),
        }
    }
};
