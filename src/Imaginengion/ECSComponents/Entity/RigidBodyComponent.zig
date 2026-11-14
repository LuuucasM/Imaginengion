const std = @import("std");
const Inspector = @import("../../UI/Inspector.zig");
const Vec3 = @import("../../Math/MathTypes.zig").Vec3;
const EngineContext = @import("../../Core/EngineContext.zig");
const Material = @import("../../Physics/Material.zig");
const RigidBodyComponent = @This();

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
//where MoveTo asked a kinematic body to be by the end of the next physics step, which then lets go of it
_MoveTarget: ?Vec3(f32) = null,

pub fn Deinit(_: *RigidBodyComponent, _: *EngineContext, _: std.mem.Allocator) void {}

pub fn UIRender(self: *RigidBodyComponent, ui: *Inspector.Builder) !void {
    //an edit keeps the mass at its minimum or above and the inverse mass in step (the inspector's after-edit)
    try ui.Float(&self._Mass, "Mass", .{ .Speed = 0.1, .Min = MIN_MASS });
    try ui.Vec3Field(&self.mGravityScale, "Gravity Scale", .{ .Speed = 0.05 });
    try ui.Union(&self.mMaterialData, "Material", .{});
}

pub fn GetMass(self: *const RigidBodyComponent) f32 {
    return self._Mass;
}

/// Applies continuous force to the rigid body physically accurate
/// Force must be in newtons form. It pushes until the end of the current physics step and is let go of after
/// it, so a force that should go on pushing is applied again every step: from an OnPhysicsUpdate script, which
/// runs at the start of each one. Applied from a once a frame script it only reaches the next step.
/// Only a dynamic body is moved by it, it is lost on a static or kinematic one
///
/// INPUT:
///     self: The rigid body self
///     force: The force being applied in newtons
/// OUTPUT: VOID
pub fn ApplyForce(self: *RigidBodyComponent, force: Vec3(f32)) void {
    self._Force.AddEqVec(force);
}

/// Applies a one time force to the rigid body. Only a dynamic body is moved by it, it is lost on a static or
/// kinematic one
///
/// INPUT:
///     self: the rigid body
///     impulse: the impulse to add
/// OUTPUT: VOID
pub fn ApplyImpulse(self: *RigidBodyComponent, impulse: Vec3(f32)) void {
    self._Velocity.AddEqVec(impulse.MulScalar(self._InvMass));
}

/// Directly set the velocity of the rigid body. On a dynamic body this shouldnt be used to simply move an object
/// But rather in less common situations where the velocity change does not need to be physically accurate.
/// On a kinematic body it is the way to move it: it goes on at this velocity until it is given another, or
/// something its collision filter blocks stops it. To send one to a position, see MoveTo
///
/// INPUT:
///     self: the rigid body
///     velocity: the new velocity to be set
/// OUTPUT: VOID
pub fn SetVelocity(self: *RigidBodyComponent, velocity: Vec3(f32)) void {
    self._Velocity = velocity;
}

/// Moves a kinematic body to a position by the end of the next physics step, then stops it. The step gives it the
/// velocity that gets it there, so what it hits or carries on the way feels that speed, which setting its translation
/// does not give them. To follow a path, call it every step from an OnPhysicsUpdate script. From a once a frame script
/// it reaches the next step. It is lost on a dynamic or static body, and when asked for during the step's own substeps
/// (an OnPreSolve script). A static or kinematic body its collision filter blocks stops it short of the position
///
/// INPUT:
///     self: the rigid body
///     target: where to be, in the same space as Entity.SetTranslation
/// OUTPUT: VOID
pub fn MoveTo(self: *RigidBodyComponent, target: Vec3(f32)) void {
    self._MoveTarget = target;
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
