const std = @import("std");
const Entity = @import("../ECSObjects/Entity.zig");

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const ColliderComponent = EntityComponents.ColliderComponent;
const TransformComponent = EntityComponents.TransformComponent;

const SDF = @import("../Math/SDFFunctions.zig");
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
    //points from mOrigin to mTarget
    mNormal: Vec3(f32),
    //the gap between the two along mNormal: negative while they overlap, by how deep
    mSeparation: f32,

    //what the solver found and did on this substep, see CollisionManager.SolveVelocities
    //how fast the two were closing along mNormal before the solver did anything, which the bounce is worked out from
    mApproachSpeed: f32 = 0,
    //how hard the solver pushed them apart, in total. Above 0 means they really met, gap or not
    mImpulse: f32 = 0,
    //the restitution they bounced with, 0 if they did not bounce
    mBounce: f32 = 0,
    //a trigger pair that was apart and whose path this substep went into each other, see SweepShapes. It
    //touches although no snapshot ever found it overlapping
    mCrossed: bool = false,
};

//the most steps SweepShapes takes along a path before giving up on it
const SWEEP_MAX_STEPS: u32 = 32;
//how close a sweep has to get to count as a hit. Sphere tracing nears a surface in ever smaller steps
//and never quite lands on it
const SWEEP_HIT_DISTANCE: f32 = 0.001;

/// What a collision script is told about a contact, from the side of the entity the script belongs to.
/// The same for every collision script type, so begin, stay and end scripts all share one Run signature
pub const CollisionInfo = struct {
    //points from the script's own entity toward the other one. zero once the two no longer overlap
    mNormal: Vec3(f32),
    //one of the two colliders is a trigger, so they pass through each other instead of being pushed apart
    mIsTrigger: bool,
};

/// Works out the gap and the direction between two colliders, whether or not they touch, and returns whether
/// they overlap. Every test is an SDF evaluation:
///   - a sphere against anything: the other collider's SDF at the sphere's centre, less the radius (ShapeSphere)
///   - box against box: the SDF of the two boxes added together (BoxBox)
/// The switch is exhaustive on purpose, so a new shape will not compile until every pairing with it has a test.
pub fn TestShapes(contact: *Contact, origin_transform_comp: *TransformComponent, origin_collider: *ColliderComponent, target_transform_comp: *TransformComponent, target_collider: *ColliderComponent) bool {
    switch (origin_collider.mShape) {
        .Sphere => SphereShape(contact, origin_transform_comp, origin_collider, target_transform_comp, target_collider),
        .Box => switch (target_collider.mShape) {
            .Sphere => ShapeSphere(contact, origin_transform_comp, origin_collider, target_transform_comp, target_collider),
            .Box => BoxBox(contact, origin_transform_comp, origin_collider, target_transform_comp, target_collider),
        },
    }
    //touching exactly is not an overlap
    return contact.mSeparation < 0.0;
}

/// Whether the pair meets as the target moves by `motion` relative to the origin. Sphere tracing, the same as the
/// renderer's ray marching, through the gap TestShapes measures: each step moves the target on by the gap, which
/// nothing is closer than, so it can never step past a surface, and it stops at a hit (within SWEEP_HIT_DISTANCE)
/// or once the whole motion is covered. Rotation is honoured wherever TestShapes honours it.
/// On a hit the contact's normal is the one at the hit point. A path that grazes a surface nears it in ever
/// smaller steps, so running out of SWEEP_MAX_STEPS without a hit counts as a miss.
pub fn SweepShapes(contact: *Contact, origin_transform_comp: *TransformComponent, origin_collider: *ColliderComponent, target_transform_comp: *TransformComponent, target_collider: *ColliderComponent, motion: Vec3(f32)) bool {
    const length = motion.Len();
    if (length <= 0.0) return false;
    const direction = motion.DivScalar(length);

    //a copy that is moved along the path, the real transform stays where it is
    var moved_target = target_transform_comp.*;
    const start = target_transform_comp.GetWorldPosition();

    var probe = contact.*;
    var travelled: f32 = 0.0;
    for (0..SWEEP_MAX_STEPS) |_| {
        moved_target.SetWorldPosition(start.AddVec(direction.MulScalar(travelled)));
        _ = TestShapes(&probe, origin_transform_comp, origin_collider, &moved_target, target_collider);

        if (probe.mSeparation <= SWEEP_HIT_DISTANCE) {
            contact.mNormal = probe.mNormal;
            return true;
        }

        travelled += probe.mSeparation;
        if (travelled >= length) return false;
    }
    return false;
}

/// Any collider against a sphere. The sphere's centre is taken into the other collider's own space, where that
/// collider's SDF gives the distance to its surface and the SDF's gradient the direction out of it. The sphere's
/// radius off the distance is the gap. The collider's rotation is honoured here, since it is undone on the point.
/// The normal points from the collider to the sphere, like every other test's origin to target.
fn ShapeSphere(contact: *Contact, shape_transform_comp: *TransformComponent, shape_collider: *ColliderComponent, sphere_transform_comp: *TransformComponent, sphere_collider: *ColliderComponent) void {
    const shape_rotation = shape_transform_comp.GetWorldRotation();
    const shape_scale = shape_transform_comp.GetWorldScale();
    const local_center = SDF.GetLocalPoint(sphere_transform_comp.GetWorldPosition(), shape_transform_comp.GetWorldPosition(), shape_rotation);

    const radius = sphere_collider.GetWorldRadius(sphere_transform_comp.GetWorldScale());

    contact.mSeparation = shape_collider.LocalDistance(local_center, shape_scale) - radius;
    //back out of the collider's own space
    contact.mNormal = shape_collider.LocalNormal(local_center, shape_scale).QuatRotate(shape_rotation);
}

/// ShapeSphere with the roles swapped: the normal points from the sphere to the other collider.
fn SphereShape(contact: *Contact, sphere_transform_comp: *TransformComponent, sphere_collider: *ColliderComponent, shape_transform_comp: *TransformComponent, shape_collider: *ColliderComponent) void {
    ShapeSphere(contact, shape_transform_comp, shape_collider, sphere_transform_comp, sphere_collider);
    contact.mNormal = contact.mNormal.Neg();
}

/// Two boxes are apart by exactly the distance from one's centre to a box the size of both put together,
/// placed on the other's centre: sdBox of the offset between them against their half extents added up. Outside
/// that is the true gap, inside it is minus the overlap on the least overlapping axis, and gradBox gives the
/// direction either way. Axis aligned: the boxes' rotations are ignored. Two rotated boxes have no such shape,
/// they need a separating axis test instead.
fn BoxBox(contact: *Contact, origin_transform_comp: *TransformComponent, origin_collider: *ColliderComponent, target_transform_comp: *TransformComponent, target_collider: *ColliderComponent) void {
    const delta = target_transform_comp.GetWorldPosition().SubVec(origin_transform_comp.GetWorldPosition());
    const half_sum = origin_collider.GetWorldHalfExtents(origin_transform_comp.GetWorldScale()).AddVec(target_collider.GetWorldHalfExtents(target_transform_comp.GetWorldScale()));

    contact.mSeparation = SDF.sdBox(delta, half_sum);
    contact.mNormal = SDF.gradBox(delta, half_sum);
}
