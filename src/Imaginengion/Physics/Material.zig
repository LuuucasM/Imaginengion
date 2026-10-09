const std = @import("std");
const Inspector = @import("../UI/Inspector.zig");
const SurfMat = @import("SurfaceMaterial.zig");
const MedMat = @import("MediumMaterial.zig");
const ImguiManager = @import("../Imgui/Imgui.zig");

const MathTypes = @import("../Math/MathTypes.zig");
const Vec4 = MathTypes.Vec4;

pub const SurfacePhysicsMat = struct {
    Kind: SurfMat.SurfaceMaterials,
    Scale: SurfMat.SurfPhysicsData,

    //Custom's base values are all 1, so its Scale is the material itself. The identity scale would
    //make every new body perfectly bouncy and very grippy; a new body does not bounce until it is given
    //restitution, and grips with 0.6, the usual default friction (Box2D's, Unity's)
    pub const default: SurfacePhysicsMat = .{
        .Kind = .Custom,
        .Scale = .{
            .Restitution = 0.0,
            .StaticFriction = DEFAULT_FRICTION,
            .KineticFriction = DEFAULT_FRICTION,
        },
    };
    const DEFAULT_FRICTION: f32 = 0.6;

    pub fn UIRender(self: *SurfacePhysicsMat, ui: *Inspector.Builder) !void {
        try ui.Enum(SurfMat.SurfaceMaterials, &self.Kind, "Surface", .{});
        try ui.Struct(&self.Scale, "Scale");
    }

    pub fn ImguiRender(self: *SurfacePhysicsMat) !void {
        try ImguiManager.RenderEnum(SurfMat.SurfaceMaterials, &self.Kind, "Surface Material");
        try self.Scale.ImguiRender("Scale");
    }

    pub fn GetMaterialData(self: SurfacePhysicsMat) SurfMat.SurfPhysicsData {
        return SurfMat.SurfaceDatabase.get(self.Kind).PhysicsData;
    }

    pub fn GetScaleData(self: SurfacePhysicsMat) SurfMat.SurfPhysicsData {
        return self.Scale;
    }

    pub fn GetScaledMaterial(self: SurfacePhysicsMat) SurfMat.SurfPhysicsData {
        const material_data = self.GetMaterialData();
        const scale_data = self.GetScaleData();
        return .{
            .Restitution = material_data.Restitution * scale_data.Restitution,
            .StaticFriction = material_data.StaticFriction * scale_data.StaticFriction,
            .KineticFriction = material_data.KineticFriction * scale_data.KineticFriction,
        };
    }
};

pub const MediumPhysicsMat = struct {
    Kind: MedMat.MediumMaterials,
    Scale: MedMat.MedPhysicsData,

    pub const default: MediumPhysicsMat = .{
        .Kind = .Custom,
        .Scale = MedMat.MediumScaleIdentity.PhysicsData,
    };

    pub fn UIRender(self: *MediumPhysicsMat, ui: *Inspector.Builder) !void {
        try ui.Enum(MedMat.MediumMaterials, &self.Kind, "Medium", .{});
        try ui.Struct(&self.Scale, "Scale");
    }

    pub fn ImguiRender(self: *MediumPhysicsMat) !void {
        try ImguiManager.RenderEnum(MedMat.MediumMaterials, &self.Kind, "Medium Material");
        try self.Scale.ImguiRender("Scale");
    }

    pub fn GetMaterialData(self: MediumPhysicsMat) MedMat.MedPhysicsData {
        return MedMat.MediumDatabase.get(self.Kind).PhysicsData;
    }

    pub fn GetScaledData(self: MediumPhysicsMat) MedMat.MedPhysicsData {
        return self.Scale;
    }

    pub fn GetScaledMaterial(self: MediumPhysicsMat) MedMat.MedPhysicsData {
        const material_data = self.GetMaterialData();
        const scale_data = self.GetScaledData();
        _ = material_data;
        _ = scale_data;
        return .{};
    }
};

/// A surface's two friction coefficients, see PhysicsMaterial.GetFriction
pub const Friction = struct {
    Static: f32,
    Kinetic: f32,
};

pub const PhysicsMaterial = union(enum) {
    Surface: SurfacePhysicsMat,
    Medium: MediumPhysicsMat,

    pub const default: PhysicsMaterial = .{ .Surface = .default };

    /// How bouncy a surface is, 0 to 1. A medium (air, water) has no surface to bounce off, so it is 0
    pub fn GetRestitution(self: PhysicsMaterial) f32 {
        return switch (self) {
            .Surface => |s| s.GetScaledMaterial().Restitution,
            .Medium => 0.0,
        };
    }

    /// How much a surface grips what slides on it: the static friction holds what is (near enough) still, the kinetic
    /// friction drags on what is already sliding. A medium has no surface to grip with, so it is 0
    pub fn GetFriction(self: PhysicsMaterial) Friction {
        return switch (self) {
            .Surface => |s| blk: {
                const scaled = s.GetScaledMaterial();
                break :blk .{ .Static = scaled.StaticFriction, .Kinetic = scaled.KineticFriction };
            },
            .Medium => .{ .Static = 0.0, .Kinetic = 0.0 },
        };
    }

    pub fn GetMaterialData(self: PhysicsMaterial) union(enum) {
        Surface: SurfMat.SurfPhysicsData,
        Medium: MedMat.MedPhysicsData,
    } {
        return switch (self) {
            .Surface => |s| .{ .Surface = s.GetMaterialData() },
            .Medium => |m| .{ .Medium = m.GetMaterialData() },
        };
    }

    pub fn GetScaleData(self: PhysicsMaterial) union(enum) {
        Surface: SurfMat.SurfPhysicsData,
        Medium: MedMat.MedPhysicsData,
    } {
        return switch (self) {
            .Surface => |s| .{ .Surface = s.GetScaleData() },
            .Medium => |m| .{ .Medium = m.GetScaledData() },
        };
    }

    pub fn GetScaledMaterial(self: PhysicsMaterial) union(enum) {
        Surface: SurfMat.SurfPhysicsData,
        Medium: MedMat.MedPhysicsData,
    } {
        return switch (self) {
            .Surface => |s| .{ .Surface = s.GetScaledMaterial() },
            .Medium => |m| .{ .Medium = m.GetScaledMaterial() },
        };
    }

    pub fn ImguiRender(self: *PhysicsMaterial) !void {
        switch (self.*) {
            .Surface => |*s| try s.ImguiRender(),
            .Medium => |*m| try m.ImguiRender(),
        }
    }
};

pub const SurfaceRenderMat = struct {
    Kind: SurfMat.SurfaceMaterials,
    Scale: SurfMat.SurfRenderData,

    pub const default: SurfaceRenderMat = .{
        .Kind = .Custom,
        .Scale = SurfMat.SurfaceScaleIdentity.RenderData,
    };

    pub fn UIRender(self: *SurfaceRenderMat, ui: *Inspector.Builder) !void {
        try ui.Enum(SurfMat.SurfaceMaterials, &self.Kind, "Surface", .{});
        try ui.Struct(&self.Scale, "Scale");
    }

    pub fn ImguiRender(self: *SurfaceRenderMat) !void {
        try ImguiManager.RenderEnum(SurfMat.SurfaceMaterials, &self.Kind, "Surface Material");
        try self.Scale.ImguiRender("Scale");
    }

    pub fn GetMaterialData(self: SurfaceRenderMat) SurfMat.SurfRenderData {
        return SurfMat.SurfaceDatabase.get(self.Kind).RenderData;
    }

    pub fn GetScaleData(self: SurfaceRenderMat) SurfMat.SurfRenderData {
        return self.Scale;
    }

    pub fn GetScaledMaterial(self: SurfaceRenderMat) SurfMat.SurfRenderData {
        const material_data = self.GetMaterialData();
        const scale_data = self.GetScaleData();
        _ = material_data;
        _ = scale_data;
        return .{}; //fill in once theres something for surface render data
    }
};

pub const MediumRenderMat = struct {
    Kind: MedMat.MediumMaterials,
    Scale: MedMat.MedRenderData,

    pub const default: MediumRenderMat = .{
        .Kind = .Custom,
        .Scale = MedMat.MediumScaleIdentity.RenderData,
    };

    pub fn UIRender(self: *MediumRenderMat, ui: *Inspector.Builder) !void {
        try ui.Enum(MedMat.MediumMaterials, &self.Kind, "Medium", .{});
        try ui.Struct(&self.Scale, "Scale");
        try ui.Color(&self.Color, "Color", .{});
    }

    pub fn ImguiRender(self: *MediumRenderMat) !void {
        try ImguiManager.RenderEnum(MedMat.MediumMaterials, &self.Kind, "Medium Material");
        try self.Scale.ImguiRender("Scale");
        try ImguiManager.RenderVec4(&self.Color, "Color", 1.0, 0.01, 100);
    }

    pub fn GetMaterialData(self: MediumRenderMat) MedMat.MedRenderData {
        return MedMat.MediumDatabase.get(self.Kind).RenderData;
    }

    pub fn GetScaledData(self: MediumRenderMat) MedMat.MedRenderData {
        return self.Scale;
    }

    pub fn GetScaledMaterial(self: MediumRenderMat) MedMat.MedRenderData {
        const material_data = self.GetMaterialData();
        const scale_data = self.GetScaledData();

        return .{
            .Absorption = material_data.Absorption.MulVec(scale_data.Absorption),
            .Scattering = material_data.Scattering.MulVec(scale_data.Scattering),
        };
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
            .Surface => |s| .{ .Surface = s.GetMaterialData() },
            .Medium => |m| .{ .Medium = m.GetMaterialData() },
        };
    }

    pub fn GetScaleData(self: RenderMaterial) union(enum) {
        Surface: SurfMat.SurfRenderData,
        Medium: MedMat.MedRenderData,
    } {
        return switch (self) {
            .Surface => |s| .{ .Surface = s.GetScaleData() },
            .Medium => |m| .{ .Medium = m.GetScaledData() },
        };
    }

    pub fn GetScaledMaterial(self: RenderMaterial) union(enum) {
        Surface: SurfMat.SurfRenderData,
        Medium: MedMat.MedRenderData,
    } {
        return switch (self) {
            .Surface => |s| s.GetScaledMaterial(),
            .Medium => |m| m.GetScaledMaterial(),
        };
    }

    pub fn ImguiRender(self: *RenderMaterial) !void {
        switch (self) {
            .Surface => |s| try s.ImguiRender(),
            .Medium => |m| try m.ImguiRender(),
        }
    }
};
