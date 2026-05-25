const std = @import("std");
const Entity = @import("../GameObjects/Entity.zig");

const EntityComponents = @import("../GameObjects/Components.zig");
const ColliderComponent = EntityComponents.ColliderComponent;

const Sphere = ColliderComponent.Sphere;
const Box = ColliderComponent.Box;

const MathUtils = @import("../Math/MathUtils.zig");
const MathTypes = @import("../Math/MathTypes.zig");
const Vec3 = MathTypes.Vec3;

pub const Contact = struct {
    mOrigin: Entity = .{},
    mTarget: Entity = .{},
    mNormal: Vec3(f32),
    mPenetration: f32,
};

pub fn SphereSphere(origin_pos: Vec3(f32), origin_scale: Vec3(f32), target_pos: Vec3(f32), target_scale: Vec3(f32)) ?Contact {
    const delta = target_pos.SubVec(origin_pos);

    const dist = delta.Len();
    const radius_sum = origin_scale.x + target_scale.x;

    if (dist >= radius_sum) return null; //not a collision

    const penetration = radius_sum - dist;

    var normal = std.mem.zeroes(Vec3(f32));

    if (dist > 0.00001) {
        normal = delta.DivScalar(dist);
    } else {
        normal.x = 1;
    }

    return Contact{
        .mNormal = normal,
        .mPenetration = penetration,
    };
}

pub fn BoxBox(origin_pos: Vec3(f32), origin_scale: Vec3(f32), target_pos: Vec3(f32), target_scale: Vec3(f32)) ?Contact {
    const delta = target_pos.SubVec(origin_pos);

    const overlap_x = (origin_scale.x + target_scale.x) - @abs(delta.x);
    const overlap_y = (origin_scale.y + target_scale.y) - @abs(delta.y);
    const overlap_z = (origin_scale.z + target_scale.z) - @abs(delta.z);

    if (overlap_x <= 0 or overlap_y <= 0 or overlap_z <= 0) return null; //not a collision

    var penetration = overlap_x;
    var normal = Vec3(f32){ .x = MathUtils.Sign(delta.x), .y = 0.0, .z = 0.0 };

    if (overlap_y < penetration) {
        penetration = overlap_y;
        normal = Vec3(f32){ .x = 0.0, .y = MathUtils.Sign(delta.y), .z = 0.0 };
    }
    if (overlap_z < penetration) {
        penetration = overlap_z;
        normal = Vec3(f32){ .x = 0.0, .y = 0.0, .z = MathUtils.Sign(delta.z) };
    }

    return Contact{
        .mNormal = normal,
        .mPenetration = penetration,
    };
}
