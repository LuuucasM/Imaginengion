const std = @import("std");
const Collisions = @import("../../Physics/Collisions.zig");
const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const ColliderComponent = EntityComponents.ColliderComponent;
const TransformComponent = EntityComponents.TransformComponent;
const Vec3 = @import("../../Math/MathTypes.zig").Vec3;

const eps: f32 = 0.0001;

const ONE = Vec3(f32){ .x = 1, .y = 1, .z = 1 };

/// A transform whose world values are already worked out, as the transform pass would leave them.
fn PlacedAt(position: Vec3(f32), scale: Vec3(f32)) TransformComponent {
    var transform: TransformComponent = .{};
    transform.SetWorldPosition(position);
    transform.SetWorldScale(scale);
    return transform;
}

fn EmptyContact() Collisions.Contact {
    return .{ .mNormal = .{ .x = 0, .y = 0, .z = 0 }, .mPenetration = 0 };
}

fn Box(size: Vec3(f32)) ColliderComponent {
    return .{ .mShape = .Box, .mBoxSize = size };
}

fn Sphere(radius: f32) ColliderComponent {
    return .{ .mShape = .Sphere, .mRadius = radius };
}

test "default box colliders are the size of a default quad" {
    //a quad of size 1 at scale 1 spans 1 unit, so two of them overlap only when closer than 1
    var a_transform = PlacedAt(.{ .x = 0, .y = 0, .z = 0 }, ONE);
    var a_collider = Box(ONE);
    var b_collider = Box(ONE);

    var contact = EmptyContact();
    var near = PlacedAt(.{ .x = 0.9, .y = 0, .z = 0 }, ONE);
    try std.testing.expect(Collisions.BoxBox(&contact, &a_transform, &a_collider, &near, &b_collider));
    try std.testing.expectApproxEqAbs(@as(f32, 0.1), contact.mPenetration, eps);
    try std.testing.expectEqual(@as(f32, 1), contact.mNormal.x);

    //touching exactly, and further apart, are not collisions
    var touching = PlacedAt(.{ .x = 1.0, .y = 0, .z = 0 }, ONE);
    try std.testing.expect(!Collisions.BoxBox(&contact, &a_transform, &a_collider, &touching, &b_collider));
    var far = PlacedAt(.{ .x = 1.1, .y = 0, .z = 0 }, ONE);
    try std.testing.expect(!Collisions.BoxBox(&contact, &a_transform, &a_collider, &far, &b_collider));
}

test "box size and scale multiply" {
    //size 2 wide at scale 2 is 4 wide, a half extent of 2. with a default box's 0.5 that's 2.5
    var big_transform = PlacedAt(.{ .x = 0, .y = 0, .z = 0 }, .{ .x = 2, .y = 2, .z = 2 });
    var big_collider = Box(.{ .x = 2, .y = 1, .z = 1 });
    var small_collider = Box(ONE);

    var contact = EmptyContact();
    var inside = PlacedAt(.{ .x = 2.4, .y = 0, .z = 0 }, ONE);
    try std.testing.expect(Collisions.BoxBox(&contact, &big_transform, &big_collider, &inside, &small_collider));
    var outside = PlacedAt(.{ .x = 2.6, .y = 0, .z = 0 }, ONE);
    try std.testing.expect(!Collisions.BoxBox(&contact, &big_transform, &big_collider, &outside, &small_collider));

    //the y extent is only size 1 at scale 2, a half extent of 1, so 1.4 up still overlaps and 1.6 doesn't
    var above = PlacedAt(.{ .x = 0, .y = 1.4, .z = 0 }, ONE);
    try std.testing.expect(Collisions.BoxBox(&contact, &big_transform, &big_collider, &above, &small_collider));
    var clear_above = PlacedAt(.{ .x = 0, .y = 1.6, .z = 0 }, ONE);
    try std.testing.expect(!Collisions.BoxBox(&contact, &big_transform, &big_collider, &clear_above, &small_collider));
}

test "default spheres fit a default quad" {
    //radius 0.5 at scale 1 is 1 across, like the quad
    var a_transform = PlacedAt(.{ .x = 0, .y = 0, .z = 0 }, ONE);
    var a_collider = Sphere(0.5);
    var b_collider = Sphere(0.5);

    var contact = EmptyContact();
    var near = PlacedAt(.{ .x = 0, .y = 0.9, .z = 0 }, ONE);
    try std.testing.expect(Collisions.SphereSphere(&contact, &a_transform, &a_collider, &near, &b_collider));
    try std.testing.expectApproxEqAbs(@as(f32, 0.1), contact.mPenetration, eps);
    try std.testing.expectEqual(@as(f32, 1), contact.mNormal.y);

    var far = PlacedAt(.{ .x = 0, .y = 1.1, .z = 0 }, ONE);
    try std.testing.expect(!Collisions.SphereSphere(&contact, &a_transform, &a_collider, &far, &b_collider));
}

test "a sphere grows by its largest scale axis" {
    //scale 3 on y only: radius 0.5 * 3 = 1.5, plus the other's 0.5 is 2
    var stretched_transform = PlacedAt(.{ .x = 0, .y = 0, .z = 0 }, .{ .x = 1, .y = 3, .z = 1 });
    var stretched_collider = Sphere(0.5);
    var other_collider = Sphere(0.5);

    var contact = EmptyContact();
    //measured along x, not y, so the grow is even rather than along the scaled axis
    var near = PlacedAt(.{ .x = 1.9, .y = 0, .z = 0 }, ONE);
    try std.testing.expect(Collisions.SphereSphere(&contact, &stretched_transform, &stretched_collider, &near, &other_collider));
    var far = PlacedAt(.{ .x = 2.1, .y = 0, .z = 0 }, ONE);
    try std.testing.expect(!Collisions.SphereSphere(&contact, &stretched_transform, &stretched_collider, &far, &other_collider));
}

test "sphere against a box face" {
    //a default box spans 0.5 each way, so a radius 0.5 sphere touches it once its center is under 1 away
    var box_transform = PlacedAt(.{ .x = 0, .y = 0, .z = 0 }, ONE);
    var box_collider = Box(ONE);
    var sphere_collider = Sphere(0.5);

    var contact = EmptyContact();
    var near = PlacedAt(.{ .x = 0.9, .y = 0, .z = 0 }, ONE);
    try std.testing.expect(Collisions.BoxSphere(&contact, &box_transform, &box_collider, &near, &sphere_collider));
    try std.testing.expectApproxEqAbs(@as(f32, 0.1), contact.mPenetration, eps);
    //box to sphere
    try std.testing.expectApproxEqAbs(@as(f32, 1), contact.mNormal.x, eps);

    //the same pair the other way round flips the normal and keeps the depth
    try std.testing.expect(Collisions.SphereBox(&contact, &near, &sphere_collider, &box_transform, &box_collider));
    try std.testing.expectApproxEqAbs(@as(f32, 0.1), contact.mPenetration, eps);
    try std.testing.expectApproxEqAbs(@as(f32, -1), contact.mNormal.x, eps);

    var touching = PlacedAt(.{ .x = 1.0, .y = 0, .z = 0 }, ONE);
    try std.testing.expect(!Collisions.BoxSphere(&contact, &box_transform, &box_collider, &touching, &sphere_collider));
    var far = PlacedAt(.{ .x = 1.1, .y = 0, .z = 0 }, ONE);
    try std.testing.expect(!Collisions.BoxSphere(&contact, &box_transform, &box_collider, &far, &sphere_collider));
}

test "sphere against a box corner is rounder than the box" {
    //0.4 past the corner on x and y is 0.566 from it: inside a box-vs-box test, but clear of a radius 0.5 sphere
    var box_transform = PlacedAt(.{ .x = 0, .y = 0, .z = 0 }, ONE);
    var box_collider = Box(ONE);
    var sphere_collider = Sphere(0.5);

    var contact = EmptyContact();
    var past_corner = PlacedAt(.{ .x = 0.9, .y = 0.9, .z = 0 }, ONE);
    try std.testing.expect(!Collisions.BoxSphere(&contact, &box_transform, &box_collider, &past_corner, &sphere_collider));

    //0.3 past on both is 0.424 from the corner, so 0.076 deep along the diagonal
    var on_corner = PlacedAt(.{ .x = 0.8, .y = 0.8, .z = 0 }, ONE);
    try std.testing.expect(Collisions.BoxSphere(&contact, &box_transform, &box_collider, &on_corner, &sphere_collider));
    const diagonal = @sqrt(0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5 - @sqrt(0.18)), contact.mPenetration, eps);
    try std.testing.expectApproxEqAbs(@as(f32, diagonal), contact.mNormal.x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, diagonal), contact.mNormal.y, eps);
}

test "sphere center inside a box leaves through the nearest face" {
    //a 4 wide, 2 tall box: a center 0.8 up is 0.2 from the top face and 1.9 from the right one
    var box_transform = PlacedAt(.{ .x = 0, .y = 0, .z = 0 }, ONE);
    var box_collider = Box(.{ .x = 4, .y = 2, .z = 2 });
    var sphere_collider = Sphere(0.5);

    var contact = EmptyContact();
    var inside = PlacedAt(.{ .x = 0.1, .y = 0.8, .z = 0 }, ONE);
    try std.testing.expect(Collisions.BoxSphere(&contact, &box_transform, &box_collider, &inside, &sphere_collider));
    //out to the face, then the whole radius past it
    try std.testing.expectApproxEqAbs(@as(f32, 0.7), contact.mPenetration, eps);
    try std.testing.expectEqual(@as(f32, 0), contact.mNormal.x);
    try std.testing.expectEqual(@as(f32, 1), contact.mNormal.y);
    try std.testing.expectEqual(@as(f32, 0), contact.mNormal.z);
}

test "box sphere uses box size, box scale, and sphere scale" {
    //box size 2 at scale 2 is a half extent of 2; a radius 0.5 sphere at scale 2 is radius 1. touching at 3
    var box_transform = PlacedAt(.{ .x = 0, .y = 0, .z = 0 }, .{ .x = 2, .y = 2, .z = 2 });
    var box_collider = Box(.{ .x = 2, .y = 2, .z = 2 });
    var sphere_collider = Sphere(0.5);

    var contact = EmptyContact();
    var near = PlacedAt(.{ .x = 0, .y = -2.9, .z = 0 }, .{ .x = 2, .y = 2, .z = 2 });
    try std.testing.expect(Collisions.BoxSphere(&contact, &box_transform, &box_collider, &near, &sphere_collider));
    try std.testing.expectApproxEqAbs(@as(f32, 0.1), contact.mPenetration, eps);
    try std.testing.expectApproxEqAbs(@as(f32, -1), contact.mNormal.y, eps);

    var far = PlacedAt(.{ .x = 0, .y = -3.1, .z = 0 }, .{ .x = 2, .y = 2, .z = 2 });
    try std.testing.expect(!Collisions.BoxSphere(&contact, &box_transform, &box_collider, &far, &sphere_collider));
}

test "TestShapes picks the test for either ordering" {
    var box_transform = PlacedAt(.{ .x = 0, .y = 0, .z = 0 }, ONE);
    var box_collider = Box(ONE);
    var sphere_transform = PlacedAt(.{ .x = 0, .y = 0.9, .z = 0 }, ONE);
    var sphere_collider = Sphere(0.5);

    var contact = EmptyContact();
    try std.testing.expect(Collisions.TestShapes(&contact, &box_transform, &box_collider, &sphere_transform, &sphere_collider));
    try std.testing.expectApproxEqAbs(@as(f32, 1), contact.mNormal.y, eps);

    try std.testing.expect(Collisions.TestShapes(&contact, &sphere_transform, &sphere_collider, &box_transform, &box_collider));
    try std.testing.expectApproxEqAbs(@as(f32, -1), contact.mNormal.y, eps);
}
