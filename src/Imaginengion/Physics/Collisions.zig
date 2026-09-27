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

/// Runs the narrow test that fits the two colliders' shapes. The switch is exhaustive on purpose, so
/// a new shape will not compile until every pairing with it has a test.
pub fn TestShapes(contact: *Contact, origin_transform_comp: *TransformComponent, origin_collider: *ColliderComponent, target_transform_comp: *TransformComponent, target_collider: *ColliderComponent) bool {
    return switch (origin_collider.mShape) {
        .Sphere => switch (target_collider.mShape) {
            .Sphere => SphereSphere(contact, origin_transform_comp, origin_collider, target_transform_comp, target_collider),
            .Box => SphereBox(contact, origin_transform_comp, origin_collider, target_transform_comp, target_collider),
        },
        .Box => switch (target_collider.mShape) {
            .Sphere => BoxSphere(contact, origin_transform_comp, origin_collider, target_transform_comp, target_collider),
            .Box => BoxBox(contact, origin_transform_comp, origin_collider, target_transform_comp, target_collider),
        },
    };
}

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

/// Axis aligned: the box's rotation is ignored, the same as BoxBox.
/// The normal points from the box to the sphere, like every other test's origin to target.
pub fn BoxSphere(contact: *Contact, box_transform_comp: *TransformComponent, box_collider: *ColliderComponent, sphere_transform_comp: *TransformComponent, sphere_collider: *ColliderComponent) bool {
    const half = box_collider.GetWorldHalfExtents(box_transform_comp.GetWorldScale());
    const radius = sphere_collider.GetWorldRadius(sphere_transform_comp.GetWorldScale());

    //the sphere's center relative to the box's, so the box spans -half to +half on each axis
    const delta = sphere_transform_comp.GetWorldPosition().SubVec(box_transform_comp.GetWorldPosition());

    //the point on (or in) the box nearest the sphere's center
    const closest = Vec3(f32){
        .x = std.math.clamp(delta.x, -half.x, half.x),
        .y = std.math.clamp(delta.y, -half.y, half.y),
        .z = std.math.clamp(delta.z, -half.z, half.z),
    };

    const offset = delta.SubVec(closest);
    const dist_sq = offset.Dot(offset);
    if (dist_sq >= radius * radius) return false; //not a collision

    if (dist_sq > 0.00001 * 0.00001) {
        //center is outside the box: push out along the line from the nearest point to the center
        const dist = @sqrt(dist_sq);
        contact.mNormal = offset.DivScalar(dist);
        contact.mPenetration = radius - dist;
        return true;
    }

    //center is inside the box (or on its surface), so the nearest point is the center itself and gives
    //no direction. Push out through the nearest face instead, like BoxBox picks its least overlap axis:
    //the center has to travel to that face and then a full radius past it
    const face_x = half.x - @abs(delta.x);
    const face_y = half.y - @abs(delta.y);
    const face_z = half.z - @abs(delta.z);

    var face_dist = face_x;
    var normal = Vec3(f32){ .x = MathUtils.Sign(delta.x), .y = 0.0, .z = 0.0 };

    if (face_y < face_dist) {
        face_dist = face_y;
        normal = Vec3(f32){ .x = 0.0, .y = MathUtils.Sign(delta.y), .z = 0.0 };
    }
    if (face_z < face_dist) {
        face_dist = face_z;
        normal = Vec3(f32){ .x = 0.0, .y = 0.0, .z = MathUtils.Sign(delta.z) };
    }

    contact.mNormal = normal;
    contact.mPenetration = face_dist + radius;

    return true;
}

/// BoxSphere with the roles swapped: the normal points from the sphere to the box.
pub fn SphereBox(contact: *Contact, sphere_transform_comp: *TransformComponent, sphere_collider: *ColliderComponent, box_transform_comp: *TransformComponent, box_collider: *ColliderComponent) bool {
    if (!BoxSphere(contact, box_transform_comp, box_collider, sphere_transform_comp, sphere_collider)) return false;
    contact.mNormal = contact.mNormal.Neg();
    return true;
}
