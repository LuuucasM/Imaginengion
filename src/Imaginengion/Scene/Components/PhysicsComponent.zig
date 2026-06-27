const Vec3 = @import("../../Math/MathTypes.zig").Vec3;
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const EngineContext = @import("../../Core/EngineContext.zig");
const PhysicsComponent = @This();

const ImguiManager = @import("../../Imgui/Imgui.zig");

pub const Name: []const u8 = "PhysicsComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == PhysicsComponent) {
            break :blk i + 5; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

mGravity: Vec3(f32) = .{ .x = 0.0, .y = -9.81, .z = 0.0 },

pub fn Deinit(_: *PhysicsComponent, _: *EngineContext) !void {}

pub fn EditorRender(self: *PhysicsComponent, _: *EngineContext) !void {
    ImguiManager.RenderFloat3Input(&self.mGravity, "Gravity");
}
