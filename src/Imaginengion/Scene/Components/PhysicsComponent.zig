const Vec3f32 = @import("../../Math/LinAlg.zig").Vec3f32;
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const EngineContext = @import("../../Core/EngineContext.zig");
const PhysicsComponent = @This();

//imgui stuff
const imgui = @import("../../Core/CImports.zig").imgui;

pub const Category: ComponentCategory = .Unique;
pub const Name: []const u8 = "PhysicsComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == PhysicsComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

mGravity: Vec3f32 = Vec3f32{ 0.0, -9.81, 0.0 },

pub fn Deinit(_: *PhysicsComponent, _: *EngineContext) !void {}

pub fn EditorRender(self: *PhysicsComponent, _: *EngineContext) !void {
    _ = imgui.igInputFloat3("Gravity", &self.mGravity[0], "%.3f", 0);
}
