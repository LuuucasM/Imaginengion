const Vec3f32 = @import("../../Math/LinAlg.zig").Vec3f32;
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;
const EngineContext = @import("../../Core/EngineContext.zig");
const ComponentsList = @import("../Components.zig").ComponentsList;
const Entity = @import("../Entity.zig");
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
pub const Name: []const u8 = "ColliderComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == ColliderComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

mParent: Entity.Type = Entity.NullEntity,
mFirst: Entity.Type = Entity.NullEntity,
mPrev: Entity.Type = Entity.NullEntity,
mNext: Entity.Type = Entity.NullEntity,
mColliderShape: UColliderShape,

pub fn Deinit(_: *ColliderComponent, _: *EngineContext) !void {}

pub fn AsSphere(self: *ColliderComponent) *Sphere {
    return &self.mColliderShape.Sphere;
}

pub fn AsBox(self: *ColliderComponent) *Box {
    return &self.mColliderShape.Box;
}
