const std = @import("std");
const Vec3 = @import("../../Math/MathTypes.zig").Vec3;
const EngineContext = @import("../../Core/EngineContext.zig");
const ComponentsList = @import("../Components.zig").ComponentsList;
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
mUseGravity: bool = false,
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

    ImguiManager.RenderBool(&self.mUseGravity, "Use Gravity?");
}
