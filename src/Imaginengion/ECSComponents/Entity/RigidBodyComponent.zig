const std = @import("std");
const Vec3 = @import("../../Math/MathTypes.zig").Vec3;
const EngineContext = @import("../../Core/EngineContext.zig");
const Material = @import("../../Physics/Material.zig");
const RigidBodyComponent = @This();

const ImguiManager = @import("../../Imgui/Imgui.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");

pub const Editable: bool = true;
pub const Name: []const u8 = "RigidBodyComponent";

/// The least a body's mass can be. A mass of 0 would be an immovable body that still falls, and making
/// something immovable is what the static and kinematic body types are for
pub const MIN_MASS: f32 = 0.001;

//never below MIN_MASS. Set it with Entity.SetMass rather than writing it, so _InvMass follows: any other
//write is brought back to MIN_MASS or above the next time the body is synced (Entity.SyncRigidBody).
//Only a dynamic body uses it, its type is the body type tag it carries
_Mass: f32 = 1.0,
mMaterialData: Material.PhysicsMaterial = .default,
//multiplies the scene's gravity axis by axis before it is applied: 1 is the scene's gravity as it is, 0 ignores
//it, a negative falls the other way. It scales the scene's gravity, it can not point it along another axis
mGravityScale: Vec3(f32) = .{ .x = 1.0, .y = 1.0, .z = 1.0 },

//what impulses and forces are divided by: 1 / _Mass on a dynamic body, and 0 on a static or kinematic
//one, which is what makes them unpushable. Worked out by Entity.SyncRigidBody
_InvMass: f32 = 1.0,
_Velocity: Vec3(f32) = std.mem.zeroes(Vec3(f32)),
_Force: Vec3(f32) = std.mem.zeroes(Vec3(f32)),

pub fn Deinit(_: *RigidBodyComponent, _: *EngineContext) void {}

pub fn EditorRender(self: *RigidBodyComponent, _: *EngineContext) !void {
    //written straight into the field: the components panel syncs the body after this, which keeps it at
    //MIN_MASS or above and works out _InvMass again
    _ = try ImguiManager.RenderFloatInput(&self._Mass, "Mass", 0.1, 1.0);
    try ImguiManager.RenderVec3(&self.mGravityScale, "Gravity Scale", 1.0, 0.05, 100.0);
    try ImguiManager.RenderUnion(Material.PhysicsMaterial, &self.mMaterialData, "Material");
}

pub fn GetMass(self: *const RigidBodyComponent) f32 {
    return self._Mass;
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

//only the authored values are saved, the runtime state is rebuilt from them. _Mass is authored, it only has
//the underscore so it is written through Entity.SetMass
const Json = JsonUtils.JsonFields(RigidBodyComponent, .{
    .Mass = "_Mass",
    .Material = "mMaterialData",
    .GravityScale = "mGravityScale",
});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;
