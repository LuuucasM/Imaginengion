const std = @import("std");
const Inspector = @import("../../UI/Inspector.zig");
const Vec3 = @import("../../Math/MathTypes.zig").Vec3;
const EngineContext = @import("../../Core/EngineContext.zig");
const ImguiManager = @import("../../Imgui/Imgui.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const ConstantForceComponent = @This();

pub const Editable: bool = true;
pub const Name: []const u8 = "ConstantForceComponent";

/// A push that stays on a body: physics applies it at the start of every step, alongside gravity and whatever
/// scripts apply, until it is changed. For a fixed push that is either on or off (a thruster, wind, a jetpack
/// set on press and cleared on release). A push that has to be worked out each step from the body's state (a
/// spring, steering, drag) belongs in an OnPhysicsUpdate script instead.
/// On the entity with the RigidBodyComponent, and only a dynamic body is moved by it. In newtons, the same as
/// RigidBodyComponent.ApplyForce. Both fields apply at once, so one body can have wind and a thruster
//in world space: the same direction however the body is turned, e.g. wind
mForce: Vec3(f32) = .{ .x = 0, .y = 0, .z = 0 },
//in the body's own space: turns with the body, e.g. a thruster pushing along the way it faces. Turned by the
//body's world rotation at the start of each step
mLocalForce: Vec3(f32) = .{ .x = 0, .y = 0, .z = 0 },

pub fn Deinit(_: *ConstantForceComponent, _: *EngineContext) void {}

pub fn UIRender(self: *ConstantForceComponent, ui: *Inspector.Builder) !void {
    try ui.Vec3Field(&self.mForce, "World Force", .{ .Speed = 0.1 });
    try ui.Vec3Field(&self.mLocalForce, "Local Force", .{ .Speed = 0.1 });
}

pub fn EditorRender(self: *ConstantForceComponent, _: *EngineContext) !void {
    try ImguiManager.RenderVec3(&self.mForce, "World Force", 0.0, 0.1, 100.0);
    try ImguiManager.RenderVec3(&self.mLocalForce, "Local Force", 0.0, 0.1, 100.0);
}

const Json = JsonUtils.JsonFields(ConstantForceComponent, .{ .Force = "mForce", .LocalForce = "mLocalForce" });
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;
