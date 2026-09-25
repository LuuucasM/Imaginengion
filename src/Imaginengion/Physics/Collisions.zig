const std = @import("std");
const Entity = @import("../ECSObjects/Entity.zig");

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const ColliderComponent = EntityComponents.ColliderComponent;
const TransformComponent = EntityComponents.TransformComponent;

const MathUtils = @import("../Math/MathUtils.zig");
const MathTypes = @import("../Math/MathTypes.zig");
const Vec3 = MathTypes.Vec3;

pub const CollisionType = enum {
    Ignore,
    Overlap,
    Block,
};

pub const Contact = struct {
    mOrigin: Entity = .uninit,
    mTarget: Entity = .uninit,
    mNormal: Vec3(f32),
    mPenetration: f32,
};

pub fn SphereSphere(contact: *Contact, origin_transform_comp: *TransformComponent, origin_collider: *ColliderComponent, target_transform_comp: *TransformComponent, target_collider: *ColliderComponent) bool {
    const origin_pos = origin_transform_comp.GetWorldPosition();
    const target_pos = target_transform_comp.GetWorldPosition();

    const delta = target_pos.SubVec(origin_pos);

    const radius_sum = origin_collider.GetWorldRadius(origin_transform_comp.GetWorldScale()) + target_collider.GetWorldRadius(target_transform_comp.GetWorldScale());

    // Compare squared distances first to avoid paying for a sqrt on pairs
    // that don't even overlap (the common case in a broad-phase pass).
    const dist_sq = delta.Dot(delta);
    if (dist_sq >= radius_sum * radius_sum) return false; //not a collision

    const dist = @sqrt(dist_sq);
    const penetration = radius_sum - dist;

    var normal = std.mem.zeroes(Vec3(f32));

    if (dist > 0.00001) {
        normal = delta.DivScalar(dist);
    } else {
        normal.x = 1;
    }

    contact.mNormal = normal;
    contact.mPenetration = penetration;

    return true;
}

/// Axis aligned: the boxes' rotations are ignored.
pub fn BoxBox(contact: *Contact, origin_transform_comp: *TransformComponent, origin_collider: *ColliderComponent, target_transform_comp: *TransformComponent, target_collider: *ColliderComponent) bool {
    const origin_pos = origin_transform_comp.GetWorldPosition();
    const target_pos = target_transform_comp.GetWorldPosition();
    const origin_half = origin_collider.GetWorldHalfExtents(origin_transform_comp.GetWorldScale());
    const target_half = target_collider.GetWorldHalfExtents(target_transform_comp.GetWorldScale());

    const delta = target_pos.SubVec(origin_pos);

    //boxes overlap on an axis while their centers are closer than their half extents added up
    const overlap_x = (origin_half.x + target_half.x) - @abs(delta.x);
    const overlap_y = (origin_half.y + target_half.y) - @abs(delta.y);
    const overlap_z = (origin_half.z + target_half.z) - @abs(delta.z);

    if (overlap_x <= 0 or overlap_y <= 0 or overlap_z <= 0) return false; //not a collision

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

    contact.mNormal = normal;
    contact.mPenetration = penetration;

    return true;
}
