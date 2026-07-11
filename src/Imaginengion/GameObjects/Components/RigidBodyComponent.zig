const std = @import("std");
const Vec3 = @import("../../Math/MathTypes.zig").Vec3;
const EngineContext = @import("../../Core/EngineContext.zig");
const ComponentsList = @import("../Components.zig").ComponentsList;
const Material = @import("../../Physics/Material.zig");
const RigidBodyComponent = @This();

const ImguiManager = @import("../../Imgui/Imgui.zig");

pub const Editable: bool = true;
pub const Name: []const u8 = "RigidBodyComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == RigidBodyComponent) {
            break :blk i + 5; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

mMass: f32 = 0.0,
mMaterialData: Material.PhysicsMaterial = .default,

_InvMass: f32 = 0.0,
_Velocity: Vec3(f32) = std.mem.zeroes(Vec3(f32)),
_Force: Vec3(f32) = std.mem.zeroes(Vec3(f32)),

pub fn Deinit(_: *RigidBodyComponent, _: *EngineContext) !void {}

pub fn EditorRender(self: *RigidBodyComponent, _: *EngineContext) !void {
    if (ImguiManager.RenderFloatInput(&self.mMass, "Mass", 0.1, 1.0)) {
        if (self.mMass != 0.0) {
            self.mInvMass = 1.0 / self.mMass;
        } else {
            self.mInvMass = 0.0;
        }
    }
    ImguiManager.RenderUnion(Material.PhysicsMaterial, &self.mMaterialData, "Material");
}

/// Applies continuous force to the rigid body physically accurate
/// Force must be in newtons form
///
/// INPUT:
///     self: The rigid body self
///     force: The force being applied in newtons
/// OUTPUT: VOID
pub fn ApplyForce(self: *RigidBodyComponent, force: Vec3(f32)) void {
    self._Force.AddEqVec(force);
}

/// Applies a one time force to the rigid body
///
/// INPUT:
///     self: the rigid body
///     impulse: the impulse to add
/// OUTPUT: VOID
pub fn ApplyImpulse(self: *RigidBodyComponent, impulse: Vec3(f32)) void {
    self._Velocity.AddEqVec(impulse.MulScalar(self._InvMass));
}

/// Directly set the velocity of the rigid body. This shouldnt be used to simply move an object
/// But rather in less common situations where the velocity change does not need to be physically accurate
///
/// INPUT:
///     self: the rigid body
///     velocity: the new velocity to be set
/// OUTPUT: VOID
pub fn SetVelocity(self: *RigidBodyComponent, velocity: Vec3(f32)) void {
    self._Velocity = velocity;
}

/// Directly add velocity to the rigid body. This skips applying math so is not
/// physically accurate but has use cases
///
/// INPUT:
///     self: the rigid body
///     velocity: the velocity to be added to the current velocity
/// OUTPUT: void
pub fn AddVelocity(self: *RigidBodyComponent, velocity: Vec3(f32)) void {
    self._Velocity.AddEqVec(velocity);
}

///Get the velocity
pub fn GetVelocity(self: *const RigidBodyComponent) Vec3(f32) {
    return self._Velocity;
}
