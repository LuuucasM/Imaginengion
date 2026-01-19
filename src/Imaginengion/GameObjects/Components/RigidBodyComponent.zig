const Vec3f32 = @import("../../Math/LinAlg.zig").Vec3f32;
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;
const EngineContext = @import("../../Core/EngineContext.zig");
const ComponentsList = @import("../Components.zig").ComponentsList;
const RigidBodyComponent = @This();

pub const Category: ComponentCategory = .Multiple;
pub const Editable: bool = true;

mMass: f32,
mInvMass: f32,
mVelocity: Vec3f32,
mForce: Vec3f32,
mUseGravity: bool,

pub fn Deinit(_: *RigidBodyComponent, _: *EngineContext) !void {}

pub fn GetName(_: RigidBodyComponent) []const u8 {
    return "RigidBodyComponent";
}

pub fn GetInd(_: RigidBodyComponent) u32 {
    return @intCast(Ind);
}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == RigidBodyComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};
