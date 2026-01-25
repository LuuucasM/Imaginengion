const Vec3f32 = @import("../../Math/LinAlg.zig").Vec3f32;
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;
const EngineContext = @import("../../Core/EngineContext.zig");
const ComponentsList = @import("../Components.zig").ComponentsList;
const RigidBodyComponent = @This();

//IMGUI
const imgui = @import("../../Core/CImports.zig").imgui;

pub const Category: ComponentCategory = .Unique;
pub const Editable: bool = true;
pub const Name: []const u8 = "RigidBodyComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == RigidBodyComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

mMass: f32 = 0.0,
mInvMass: f32 = 0.0,
mVelocity: Vec3f32 = Vec3f32{ 0.0, 0.0, 0.0 },
mForce: Vec3f32 = Vec3f32{ 0.0, 0.0, 0.0 },
mUseGravity: bool = false,

pub fn Deinit(_: *RigidBodyComponent, _: *EngineContext) !void {}

pub fn EditorRender(self: *RigidBodyComponent, _: *EngineContext) !void {
    if (imgui.igInputFloat("Mass", &self.mMass, 0.1, 1.0, "%.3f", 9)) {
        if (self.mMass != 0.0) {
            self.mInvMass = 1.0 / self.mMass;
        } else {
            self.mInvMass = 0.0;
        }
    }
    _ = imgui.igCheckbox("Use Gravity", &self.mUseGravity);
}
