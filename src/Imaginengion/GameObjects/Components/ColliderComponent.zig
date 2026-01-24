const Vec3f32 = @import("../../Math/LinAlg.zig").Vec3f32;
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;
const EngineContext = @import("../../Core/EngineContext.zig");
const ComponentsList = @import("../Components.zig").ComponentsList;
const ColliderComponent = @This();

pub const Sphere = struct {
    mRadius: f32,
};

pub const Box = struct {
    mHalfExtents: Vec3f32,
};

pub const UColliderShape = union(enum(u8)) {
    Sphere = Sphere,
    Box = Box,
};

pub const Category: ComponentCategory = .Multiple;
pub const Editable: bool = true;

mColliderShape: UColliderShape,

pub fn Deinit(_: *ColliderComponent, _: *EngineContext) !void {}

pub fn GetName(_: ColliderComponent) []const u8 {
    return "ColliderComponent";
}

pub fn GetInd(_: ColliderComponent) u32 {
    return @intCast(Ind);
}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == ColliderComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

pub fn AsSphere(self: *ColliderComponent) *Sphere {
    return &self.mColliderShape.Sphere;
}

pub fn AsBox(self: *ColliderComponent) *Box {
    return &self.mColliderShape.Box;
}
