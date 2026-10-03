const std = @import("std");
const Entity = @import("../ECSObjects/Entity.zig");

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const ColliderComponent = EntityComponents.ColliderComponent;
const TransformComponent = EntityComponents.TransformComponent;

const SDF = @import("../Math/SDFFunctions.zig");
const MathTypes = @import("../Math/MathTypes.zig");
const Vec3 = MathTypes.Vec3;
const Quat = MathTypes.Quat;

pub const CollisionType = enum {
    Ignore,
    Overlap,
    Block,
};

pub const Contact = struct {
    //the two colliders, which the shapes are measured from
    mOrigin: Entity = .uninit,
    mTarget: Entity = .uninit,
    //the game objects they are part of (Entity.GetMainObject), whose rigid bodies the solver moves. The collider
    //itself when it is on its game object rather than on a convenience child of it
    mOriginBody: Entity = .uninit,
    mTargetBody: Entity = .uninit,
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
    //how fast the two were sliding along each other before the solver did anything, which decides whether static or
    //kinetic friction holds them
    mSlipSpeed: f32 = 0,
    //how hard friction has dragged on the target against its sliding, in total. The origin got the opposite. Never
    //longer than the friction coefficient times mImpulse
    mFrictionImpulse: Vec3(f32) = .{ .x = 0, .y = 0, .z = 0 },
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
    //which of each game object's colliders touched, for an object with several (e.g. a head and feet). The game
    //object itself when its collider is on it rather than on a convenience child
    mSelfCollider: Entity,
    mOtherCollider: Entity,
};

/// What a pre-solve script is told about a solid contact the solver is about to act on, from the side of the entity
/// the script belongs to, and the one thing it can change about it: whether the solver acts on it at all
/// (see PhysicsEventData.PreSolveEvent)
pub const PreSolveInfo = struct {
    //points from the script's own entity toward the other one
    mNormal: Vec3(f32),
    //the gap between the two along mNormal: negative while they overlap, by how deep. A contact can be handed over
    //before the two touch, when they are close enough to meet on this substep
    mSeparation: f32,
    //which of each game object's colliders this contact is between, see CollisionInfo
    mSelfCollider: Entity,
    mOtherCollider: Entity,
    //set to false and the two pass through each other this substep: the solver does not stop or push them, and
    //they do not count as touching, so a collision that began ends. It starts true and is asked again every substep
    mEnabled: bool = true,
};

/// Works out the gap and the direction between two colliders, whether or not they touch, and returns whether
/// they overlap. Each pairing of shapes has the simplest test that is right for it:
///   - a sphere against anything: the other collider's SDF at the sphere's centre, less the radius (ShapeSphere)
///   - box against box turned the same way (unturned included): the SDF of the two boxes added together (BoxBox)
///   - box against box turned differently: a separating axis test (BoxBoxSAT)
/// The switch is exhaustive on purpose, so a new shape will not compile until every pairing with it has a test.
/// A pairing with no test of its own is what a general convex test (GJK/EPA) would be for, once a shape needs one.
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
    return SweepAlong(contact, origin_transform_comp, origin_collider, target_transform_comp, target_collider, motion.DivScalar(length), length) != null;
}

/// SweepShapes given the path as a unit direction and a length, which can be +inf, and answering how far along it
/// the target got before it hit: 0 when it started touching or inside, null on a miss
pub fn SweepAlong(contact: *Contact, origin_transform_comp: *TransformComponent, origin_collider: *ColliderComponent, target_transform_comp: *TransformComponent, target_collider: *ColliderComponent, direction: Vec3(f32), length: f32) ?f32 {
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
            return travelled;
        }

        travelled += probe.mSeparation;
        if (travelled >= length) return null;
    }
    return null;
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

/// Two boxes turned the same way are apart by exactly the distance from one's centre to a box the size of both put
/// together, placed on the other's centre: sdBox of the offset between them against their half extents added up,
/// in the boxes' shared rotation. Outside that is the true gap, inside it is minus the overlap on the least
/// overlapping axis, and gradBox gives the direction either way. Rounded boxes add up the same way: each is a smaller
/// box swept by a sphere of its corner radius, so both together are the two smaller boxes added up, swept by both
/// radii added up, which is a rounded box of the half extents added up and the radii added up.
/// Boxes turned differently add up to no box at all, so those go to BoxBoxSAT instead.
fn BoxBox(contact: *Contact, origin_transform_comp: *TransformComponent, origin_collider: *ColliderComponent, target_transform_comp: *TransformComponent, target_collider: *ColliderComponent) void {
    const origin_scale = origin_transform_comp.GetWorldScale();
    const target_scale = target_transform_comp.GetWorldScale();
    const origin_box: OrientedBox = .{
        .mCenter = origin_transform_comp.GetWorldPosition(),
        .mRotation = origin_transform_comp.GetWorldRotation(),
        .mHalfExtents = origin_collider.GetWorldHalfExtents(origin_scale),
        .mCornerRadius = origin_collider.GetWorldCornerRadius(origin_scale),
    };
    const target_box: OrientedBox = .{
        .mCenter = target_transform_comp.GetWorldPosition(),
        .mRotation = target_transform_comp.GetWorldRotation(),
        .mHalfExtents = target_collider.GetWorldHalfExtents(target_scale),
        .mCornerRadius = target_collider.GetWorldCornerRadius(target_scale),
    };

    if (!SameRotation(origin_box.mRotation, target_box.mRotation)) {
        BoxBoxSAT(contact, origin_box, target_box);
        return;
    }

    //in the shared rotation both boxes line up with the axes, and back out of it after
    const local_delta = SDF.GetLocalPoint(target_box.mCenter, origin_box.mCenter, origin_box.mRotation);
    const half_sum = origin_box.mHalfExtents.AddVec(target_box.mHalfExtents);
    const radius_sum = origin_box.mCornerRadius + target_box.mCornerRadius;

    contact.mSeparation = SDF.sdRoundedBox(local_delta, half_sum, radius_sum);
    contact.mNormal = SDF.normalRoundedBox(local_delta, half_sum, radius_sum).QuatRotate(origin_box.mRotation);
}

/// A box collider in world space: what BoxBox and BoxBoxSAT need of it
const OrientedBox = struct {
    mCenter: Vec3(f32),
    mRotation: Quat(f32),
    mHalfExtents: Vec3(f32),
    mCornerRadius: f32,

    /// The box's own x, y and z axes in world space, which its faces are square to
    fn Axes(self: OrientedBox) [3]Vec3(f32) {
        return .{
            (Vec3(f32){ .x = 1, .y = 0, .z = 0 }).QuatRotate(self.mRotation),
            (Vec3(f32){ .x = 0, .y = 1, .z = 0 }).QuatRotate(self.mRotation),
            (Vec3(f32){ .x = 0, .y = 0, .z = 1 }).QuatRotate(self.mRotation),
        };
    }

    /// The half extents of the box the corner radius is swept around, see SDF.sdRoundedBox
    fn CoreHalfExtents(self: OrientedBox) Vec3(f32) {
        return self.mHalfExtents.SubVec(.FromScalar(self.mCornerRadius));
    }
};

//how close two rotations' quaternions have to be to count as the same turn. A quaternion and its negative are the
//same turn, so it is the size of their dot product that is compared
const SAME_ROTATION_DOT: f32 = 1.0 - 1e-6;

fn SameRotation(a: Quat(f32), b: Quat(f32)) bool {
    const dot = a.w * b.w + a.x * b.x + a.y * b.y + a.z * b.z;
    return @abs(dot) >= SAME_ROTATION_DOT;
}

//an edge pair's axis has to beat the best face axis by this much to be used: when they are about as good, as with
//two boxes turned only about the axis they share, the face's normal is the steadier one and the one expected
const SAT_EDGE_BIAS: f32 = 0.001;
//below this the two edges are parallel, and their cross product is no direction at all
const SAT_MIN_EDGE_AXIS: f32 = 1e-4;

/// Two boxes turned differently, by the separating axis test: two boxes are apart if and only if, along one of 15
/// directions, their shadows do not overlap. The 15 are the 3 face normals of each box, and the 9 directions square
/// to an edge of each (their axes crossed). Along each direction the gap is the distance between the centres less
/// how far each box reaches, and the largest gap is the answer, with its direction as the normal.
/// While they overlap that is exact: the least they overlap by, the way out. While they are apart it is at most the
/// true gap, and can be less near an edge or corner. Never more, so a sweep stepping by it never steps through
/// anything and a contact is found early rather than late. Rounded boxes are their core boxes measured the same way,
/// less both corner radii, which is the same sweeping by spheres BoxBox relies on.
fn BoxBoxSAT(contact: *Contact, origin: OrientedBox, target: OrientedBox) void {
    const origin_axes = origin.Axes();
    const target_axes = target.Axes();
    const origin_half = origin.CoreHalfExtents();
    const target_half = target.CoreHalfExtents();
    const delta = target.mCenter.SubVec(origin.mCenter);

    var best_gap = -std.math.inf(f32);
    var best_axis: Vec3(f32) = origin_axes[0];

    for (origin_axes ++ target_axes) |axis| {
        const gap = GapAlong(axis, delta, origin_axes, origin_half, target_axes, target_half);
        if (gap > best_gap) {
            best_gap = gap;
            best_axis = axis;
        }
    }

    for (origin_axes) |origin_axis| {
        for (target_axes) |target_axis| {
            const cross = origin_axis.Cross(target_axis);
            const length = cross.Len();
            if (length < SAT_MIN_EDGE_AXIS) continue;
            const axis = cross.DivScalar(length);

            const gap = GapAlong(axis, delta, origin_axes, origin_half, target_axes, target_half);
            if (gap > best_gap + SAT_EDGE_BIAS) {
                best_gap = gap;
                best_axis = axis;
            }
        }
    }

    //from the origin toward the target, like every other test
    contact.mNormal = if (best_axis.Dot(delta) < 0.0) best_axis.Neg() else best_axis;
    contact.mSeparation = best_gap - origin.mCornerRadius - target.mCornerRadius;
}

/// How far apart two boxes' shadows are along a unit direction: negative while they overlap, by how much
fn GapAlong(axis: Vec3(f32), delta: Vec3(f32), origin_axes: [3]Vec3(f32), origin_half: Vec3(f32), target_axes: [3]Vec3(f32), target_half: Vec3(f32)) f32 {
    return @abs(delta.Dot(axis)) - ReachAlong(axis, origin_axes, origin_half) - ReachAlong(axis, target_axes, target_half);
}

/// How far a box reaches from its centre along a unit direction: each half extent, by how much its axis points that way
fn ReachAlong(axis: Vec3(f32), box_axes: [3]Vec3(f32), half_extents: Vec3(f32)) f32 {
    return half_extents.x * @abs(box_axes[0].Dot(axis)) +
        half_extents.y * @abs(box_axes[1].Dot(axis)) +
        half_extents.z * @abs(box_axes[2].Dot(axis));
}
