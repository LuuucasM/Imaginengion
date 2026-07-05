const std = @import("std");
const Vec3 = @import("../../Math/MathTypes.zig").Vec3;
const EngineContext = @import("../../Core/EngineContext.zig");
const ComponentsList = @import("../Components.zig").ComponentsList;
const ImguiManager = @import("../../Imgui/Imgui.zig");
const Entity = @import("../Entity.zig");

const ColliderComponent = @This();

pub const Shapes = enum {
    Box,
    Sphere,
};

pub const Editable: bool = true;
pub const Name: []const u8 = "ColliderComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == ColliderComponent) {
            break :blk i + 5; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

mShape: Shapes = .Sphere,

pub fn Deinit(_: *ColliderComponent, _: *EngineContext) !void {}

pub fn EditorRender(self: *ColliderComponent, _: *EngineContext) !void {
    try ImguiManager.RenderUnion(Shapes, &self.mShape, "Collider Type");
}
