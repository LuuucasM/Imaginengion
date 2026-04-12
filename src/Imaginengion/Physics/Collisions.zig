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

pub fn SphereSphere(origin_pos: Vec3f32, origin_scale: Vec3f32, target_pos: Vec3f32, target_scale: Vec3f32) ?Contact {
    const delta = target_pos - origin_pos;

    const dist = LinAlg.Vec3Mag(delta);
    const radius_sum = origin_scale[0] + target_scale[0];

    if (dist >= radius_sum) return null; //not a collision

    const penetration = radius_sum - dist;

    var normal = std.mem.zeroes(Vec3f32);

    if (dist > 0.00001) {
        normal = delta / @as(Vec3f32, @splat(dist));
    } else {
        normal[0] = 1;
    }

    return Contact{
        .mNormal = normal,
        .mPenetration = penetration,
    };
}

pub fn BoxBox(origin_pos: Vec3f32, origin_scale: Vec3f32, target_pos: Vec3f32, target_scale: Vec3f32) ?Contact {
    const delta = target_pos - origin_pos;

    const overlap_x = (origin_scale[0] + target_scale[0]) - @abs(delta[0]);
    const overlap_y = (origin_scale[1] + target_scale[1]) - @abs(delta[1]);
    const overlap_z = (origin_scale[2] + target_scale[2]) - @abs(delta[2]);

    if (overlap_x <= 0 or overlap_y <= 0 or overlap_z <= 0) return null; //not a collision

    var penetration = overlap_x;
    var normal = Vec3f32{ LinAlg.Sign(delta[0]), 0.0, 0.0 };

    if (overlap_y < penetration) {
        penetration = overlap_y;
        normal = Vec3f32{ 0.0, LinAlg.Sign(delta[1]), 0.0 };
    }
    if (overlap_z < penetration) {
        penetration = overlap_z;
        normal = Vec3f32{ 0.0, 0.0, LinAlg.Sign(delta[2]) };
    }

    return Contact{
        .mNormal = normal,
        .mPenetration = penetration,
    };
}
