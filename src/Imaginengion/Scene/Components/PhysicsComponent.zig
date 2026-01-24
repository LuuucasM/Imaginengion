const Vec3f32 = @import("../../Math/LinAlg.zig").Vec3f32;
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const EngineContext = @import("../../Core/EngineContext.zig");
const PhysicsComponent = @This();

pub const Category: ComponentCategory = .Unique;
pub const Editable: bool = true;

mGravity: Vec3f32,

pub fn Deinit(_: *PhysicsComponent, _: *EngineContext) !void {}

pub fn GetName(_: PhysicsComponent) []const u8 {
    return "PhysicsComponent";
}

pub fn GetInd(_: PhysicsComponent) u32 {
    return @intCast(Ind);
}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == PhysicsComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};
