const Vec3 = @import("../../Math/MathTypes.zig").Vec3;
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const EngineContext = @import("../../Core/EngineContext.zig");
const PhysicsComponent = @This();

//imgui stuff
const imgui = @import("../../Core/CImports.zig").imgui;

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
    var gravity_arr = [3]f32{ self.mGravity.x, self.mGravity.y, self.mGravity.z };
    if (imgui.igInputFloat3("Gravity", &gravity_arr[0], "%.3f", 0)) {
        self.mGravity.x = gravity_arr[0];
        self.mGravity.y = gravity_arr[1];
        self.mGravity.z = gravity_arr[2];
    }
}
