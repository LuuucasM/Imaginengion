const std = @import("std");
const Entity = @import("../GameObjects/Entity.zig");
const LinAlg = @import("../Math/LinAlg.zig");

const EntityComponents = @import("../GameObjects/Components.zig");
const ColliderComponent = EntityComponents.ColliderComponent;

const Sphere = ColliderComponent.Sphere;
const Box = ColliderComponent.Box;

const Vec3f32 = LinAlg.Vec3f32;

pub const Contact = struct {
    mOrigin: Entity = .{},
    mTarget: Entity = .{},
    mNormal: Vec3f32,
    mPenetration: f32,
};

pub fn SphereSphere(sphere_origin: *Sphere, world_pos_origin: Vec3f32, sphere_target: *Sphere, world_pos_target: Vec3f32) ?Contact {
    const delta = world_pos_target - world_pos_origin;

    const dist = LinAlg.Vec3Mag(delta);
    const radius_sum = sphere_origin.mRadius + sphere_target.mRadius;

    if (dist >= radius_sum) return null; //not a collision

    const penetration = radius_sum - dist;

    const normal = std.mem.zeroes(Vec3f32);

    if (dist > 0.00001) {
        normal = delta / dist;
    } else {
        normal[0] = 1;
    }

    return Contact{
        .mNormal = normal,
        .mPenetration = penetration,
    };
}

pub fn BoxBox(box_origin: *Box, world_pos_origin: Vec3f32, box_target: *Box, world_pos_target: Vec3f32) ?Contact {
    const delta = world_pos_target - world_pos_origin;

    const overlap_x = (box_origin.mHalfExtents[0] + box_target.mHalfExtents[0]) - @abs(delta[0]);
    const overlap_y = (box_origin.mHalfExtents[1] + box_target.mHalfExtents[1]) - @abs(delta[1]);
    const overlap_z = (box_origin.mHalfExtents[2] + box_target.mHalfExtents[2]) - @abs(delta[2]);

    if (overlap_x <= 0 or overlap_y <= 0 or overlap_z <= 0) return null; //not a collision

    var penetration = overlap_x;
    var normal = Vec3f32{ 1.0, 0.0, 0.0 } * @as(Vec3f32, @splat(LinAlg.Sign(delta[0])));

    if (overlap_y < penetration) {
        penetration = overlap_y;
        normal = Vec3f32{ 0.0, 1.0, 0.0 } * @as(Vec3f32, @splat(LinAlg.Sign(delta[1])));
    }
    if (overlap_z < penetration) {
        penetration = overlap_z;
        normal = Vec3f32{ 0.0, 0.0, 1.0 } * @as(Vec3f32, @splat(LinAlg.Sign(delta[2])));
    }

    return Contact{
        .mNormal = normal,
        .mPenetration = penetration,
    };
}
