const std = @import("std");
const Collisions = @import("../../Physics/Collisions.zig");
const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const ColliderComponent = EntityComponents.ColliderComponent;
const TransformComponent = EntityComponents.TransformComponent;
const MathTypes = @import("../../Math/MathTypes.zig");
const Vec3 = MathTypes.Vec3;
const Quat = MathTypes.Quat;

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
    return .{ .mNormal = .{ .x = 0, .y = 0, .z = 0 }, .mSeparation = 0 };
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
    try std.testing.expect(Collisions.TestShapes(&contact, &a_transform, &a_collider, &near, &b_collider));
    try std.testing.expectApproxEqAbs(@as(f32, -0.1), contact.mSeparation, eps);
    try std.testing.expectEqual(@as(f32, 1), contact.mNormal.x);

    //touching exactly, and further apart, are not collisions
    var touching = PlacedAt(.{ .x = 1.0, .y = 0, .z = 0 }, ONE);
    try std.testing.expect(!Collisions.TestShapes(&contact, &a_transform, &a_collider, &touching, &b_collider));
    var far = PlacedAt(.{ .x = 1.1, .y = 0, .z = 0 }, ONE);
    try std.testing.expect(!Collisions.TestShapes(&contact, &a_transform, &a_collider, &far, &b_collider));
}

test "box size and scale multiply" {
    //size 2 wide at scale 2 is 4 wide, a half extent of 2. with a default box's 0.5 that's 2.5
    var big_transform = PlacedAt(.{ .x = 0, .y = 0, .z = 0 }, .{ .x = 2, .y = 2, .z = 2 });
    var big_collider = Box(.{ .x = 2, .y = 1, .z = 1 });
    var small_collider = Box(ONE);

    var contact = EmptyContact();
    var inside = PlacedAt(.{ .x = 2.4, .y = 0, .z = 0 }, ONE);
    try std.testing.expect(Collisions.TestShapes(&contact, &big_transform, &big_collider, &inside, &small_collider));
    var outside = PlacedAt(.{ .x = 2.6, .y = 0, .z = 0 }, ONE);
    try std.testing.expect(!Collisions.TestShapes(&contact, &big_transform, &big_collider, &outside, &small_collider));

    //the y extent is only size 1 at scale 2, a half extent of 1, so 1.4 up still overlaps and 1.6 doesn't
    var above = PlacedAt(.{ .x = 0, .y = 1.4, .z = 0 }, ONE);
    try std.testing.expect(Collisions.TestShapes(&contact, &big_transform, &big_collider, &above, &small_collider));
    var clear_above = PlacedAt(.{ .x = 0, .y = 1.6, .z = 0 }, ONE);
    try std.testing.expect(!Collisions.TestShapes(&contact, &big_transform, &big_collider, &clear_above, &small_collider));
}

test "boxes that are apart report the true gap between them" {
    var a_transform = PlacedAt(.{ .x = 0, .y = 0, .z = 0 }, ONE);
    var a_collider = Box(ONE);
    var b_collider = Box(ONE);

    var contact = EmptyContact();

    //side by side: the gap is straight across
    var beside = PlacedAt(.{ .x = 1.5, .y = 0, .z = 0 }, ONE);
    try std.testing.expect(!Collisions.TestShapes(&contact, &a_transform, &a_collider, &beside, &b_collider));
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), contact.mSeparation, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 1), contact.mNormal.x, eps);

    //corner to corner: 0.3 apart on x and 0.4 on y is 0.5 between the nearest corners, along that diagonal
    var diagonal = PlacedAt(.{ .x = 1.3, .y = 1.4, .z = 0 }, ONE);
    try std.testing.expect(!Collisions.TestShapes(&contact, &a_transform, &a_collider, &diagonal, &b_collider));
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), contact.mSeparation, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 0.6), contact.mNormal.x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), contact.mNormal.y, eps);
}

fn RoundedBox(size: Vec3(f32), corner_radius: f32) ColliderComponent {
    return .{ .mShape = .Box, .mBoxSize = size, .mCornerRadius = corner_radius };
}

test "rounding a box leaves its faces where they were" {
    var a_transform = PlacedAt(.{ .x = 0, .y = 0, .z = 0 }, ONE);
    var a_collider = RoundedBox(ONE, 0.2);
    var b_collider = RoundedBox(ONE, 0.1);

    var contact = EmptyContact();
    var beside = PlacedAt(.{ .x = 1.5, .y = 0, .z = 0 }, ONE);
    _ = Collisions.TestShapes(&contact, &a_transform, &a_collider, &beside, &b_collider);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), contact.mSeparation, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 1), contact.mNormal.x, eps);
}

test "two rounded boxes are as far apart at a corner as their roundings add up to" {
    //unit boxes rounded by 0.2 and 0.1: together a box of half extents 1 rounded by 0.3, whose corner is swept around
    //a point 0.7 out on each axis. 1.1 diagonally is 0.4 past that point on x and y, 0.4 * sqrt(2) away, less 0.3
    var a_transform = PlacedAt(.{ .x = 0, .y = 0, .z = 0 }, ONE);
    var a_collider = RoundedBox(ONE, 0.2);
    var b_collider = RoundedBox(ONE, 0.1);

    var contact = EmptyContact();
    var diagonal = PlacedAt(.{ .x = 1.1, .y = 1.1, .z = 0 }, ONE);
    _ = Collisions.TestShapes(&contact, &a_transform, &a_collider, &diagonal, &b_collider);
    try std.testing.expectApproxEqAbs(@as(f32, 0.4 * std.math.sqrt2 - 0.3), contact.mSeparation, eps);
    try std.testing.expectApproxEqAbs(std.math.sqrt1_2, contact.mNormal.x, eps);
    try std.testing.expectApproxEqAbs(std.math.sqrt1_2, contact.mNormal.y, eps);

    //sharp, the same two are only 0.1 * sqrt(2) apart there
    var sharp_a = Box(ONE);
    var sharp_b = Box(ONE);
    _ = Collisions.TestShapes(&contact, &a_transform, &sharp_a, &diagonal, &sharp_b);
    try std.testing.expectApproxEqAbs(@as(f32, 0.1 * std.math.sqrt2), contact.mSeparation, eps);
}

test "a box's rounding grows with its smallest scale axis and can't pass its smallest half extent" {
    const collider = RoundedBox(ONE, 0.2);
    try std.testing.expectApproxEqAbs(@as(f32, 0.4), collider.GetWorldCornerRadius(.{ .x = 2, .y = 3, .z = 2 }), eps);

    //a box half a unit thick can be rounded by a quarter at most, which makes that side a half circle
    const thin = RoundedBox(.{ .x = 2, .y = 0.5, .z = 2 }, 1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), thin.GetWorldCornerRadius(ONE), eps);
}

test "a sphere sees a box's rounded corner" {
    //a unit box rounded by 0.2 has its corner swept around a point 0.3 out on each axis
    var box_transform = PlacedAt(.{ .x = 0, .y = 0, .z = 0 }, ONE);
    var box_collider = RoundedBox(ONE, 0.2);
    var sphere_collider = Sphere(0.1);

    var contact = EmptyContact();
    var diagonal = PlacedAt(.{ .x = 0.6, .y = 0.6, .z = 0 }, ONE);
    _ = Collisions.TestShapes(&contact, &box_transform, &box_collider, &diagonal, &sphere_collider);
    try std.testing.expectApproxEqAbs(@as(f32, 0.3 * std.math.sqrt2 - 0.2 - 0.1), contact.mSeparation, eps);
}

/// PlacedAt, turned about z, the way a top down car or a 2D game's boxes turn
fn PlacedTurned(position: Vec3(f32), size_scale: Vec3(f32), degrees_about_z: f32) TransformComponent {
    var transform = PlacedAt(position, size_scale);
    transform.SetWorldRotation(Quat(f32).FromAxisAngle(.{ .x = 0, .y = 0, .z = 1 }, std.math.degreesToRadians(degrees_about_z)));
    return transform;
}

test "a box turned on its corner beside an unturned one is apart by the gap to that corner" {
    //turned 45 degrees a unit box reaches sqrt(2) / 2 along x, so from 1.5 away the corner is 1.5 - 0.5 - 0.7071 off
    //the unturned box's face
    var flat_transform = PlacedAt(.{ .x = 0, .y = 0, .z = 0 }, ONE);
    var flat_collider = Box(ONE);
    var turned_collider = Box(ONE);

    var contact = EmptyContact();
    var turned = PlacedTurned(.{ .x = 1.5, .y = 0, .z = 0 }, ONE, 45);
    try std.testing.expect(!Collisions.TestShapes(&contact, &flat_transform, &flat_collider, &turned, &turned_collider));
    try std.testing.expectApproxEqAbs(@as(f32, 1.0 - std.math.sqrt1_2), contact.mSeparation, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 1), contact.mNormal.x, eps);

    //half a unit closer the corner is in by the same less a half
    var closer = PlacedTurned(.{ .x = 1.0, .y = 0, .z = 0 }, ONE, 45);
    try std.testing.expect(Collisions.TestShapes(&contact, &flat_transform, &flat_collider, &closer, &turned_collider));
    try std.testing.expectApproxEqAbs(@as(f32, 0.5 - std.math.sqrt1_2), contact.mSeparation, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 1), contact.mNormal.x, eps);

    //the normal points from the origin to the target whichever way round they are
    try std.testing.expect(Collisions.TestShapes(&contact, &closer, &turned_collider, &flat_transform, &flat_collider));
    try std.testing.expectApproxEqAbs(@as(f32, -1), contact.mNormal.x, eps);
}

test "a long box turned a quarter turn collides as its turned self" {
    //2 long and 0.5 wide: turned upright it is only 0.25 wide on x, so a unit box 0.9 away is clear of it by 0.15.
    //Unturned it would reach 1 along x and overlap
    var car_collider = Box(.{ .x = 2, .y = 0.5, .z = 1 });
    var wall_collider = Box(ONE);
    var upright_car = PlacedTurned(.{ .x = 0, .y = 0, .z = 0 }, ONE, 90);
    var wall = PlacedAt(.{ .x = 0.9, .y = 0, .z = 0 }, ONE);

    var contact = EmptyContact();
    try std.testing.expect(!Collisions.TestShapes(&contact, &upright_car, &car_collider, &wall, &wall_collider));
    try std.testing.expectApproxEqAbs(@as(f32, 0.15), contact.mSeparation, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 1), contact.mNormal.x, eps);
}

test "two boxes turned the same way are measured exactly in their shared turn" {
    //both 2 long and turned upright, one stacked 2.1 above the other: 0.1 apart along y, and the normal is back in
    //world space
    var collider = Box(.{ .x = 2, .y = 0.5, .z = 1 });
    var lower = PlacedTurned(.{ .x = 0, .y = 0, .z = 0 }, ONE, 90);
    var upper = PlacedTurned(.{ .x = 0, .y = 2.1, .z = 0 }, ONE, 90);

    var contact = EmptyContact();
    try std.testing.expect(!Collisions.TestShapes(&contact, &lower, &collider, &upper, &collider));
    try std.testing.expectApproxEqAbs(@as(f32, 0.1), contact.mSeparation, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 1), contact.mNormal.y, eps);

    //a diagonal gap is the true distance to the corner, not the SAT's lower bound along one axis
    var diagonal = PlacedTurned(.{ .x = 0.6, .y = 2.1, .z = 0 }, ONE, 90);
    _ = Collisions.TestShapes(&contact, &lower, &collider, &diagonal, &collider);
    try std.testing.expectApproxEqAbs(@as(f32, 0.1 * std.math.sqrt2), contact.mSeparation, eps);
}

test "rounded turned boxes are their core boxes less both corner radii" {
    var flat_transform = PlacedAt(.{ .x = 0, .y = 0, .z = 0 }, ONE);
    var flat_collider = RoundedBox(ONE, 0.1);
    var turned_collider = RoundedBox(ONE, 0.2);

    //the cores are 0.4 and 0.3 half wide, the turned one's reaching 0.3 * sqrt(2) along x, then both radii come off
    var contact = EmptyContact();
    var turned = PlacedTurned(.{ .x = 1.5, .y = 0, .z = 0 }, ONE, 45);
    _ = Collisions.TestShapes(&contact, &flat_transform, &flat_collider, &turned, &turned_collider);
    try std.testing.expectApproxEqAbs(@as(f32, 1.5 - 0.4 - 0.3 * std.math.sqrt2 - 0.3), contact.mSeparation, eps);
}

test "default spheres fit a default quad" {
    //radius 0.5 at scale 1 is 1 across, like the quad
    var a_transform = PlacedAt(.{ .x = 0, .y = 0, .z = 0 }, ONE);
    var a_collider = Sphere(0.5);
    var b_collider = Sphere(0.5);

    var contact = EmptyContact();
    var near = PlacedAt(.{ .x = 0, .y = 0.9, .z = 0 }, ONE);
    try std.testing.expect(Collisions.TestShapes(&contact, &a_transform, &a_collider, &near, &b_collider));
    try std.testing.expectApproxEqAbs(@as(f32, -0.1), contact.mSeparation, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 1), contact.mNormal.y, eps);

    //apart, the gap is the distance between the surfaces
    var far = PlacedAt(.{ .x = 0, .y = 1.1, .z = 0 }, ONE);
    try std.testing.expect(!Collisions.TestShapes(&contact, &a_transform, &a_collider, &far, &b_collider));
    try std.testing.expectApproxEqAbs(@as(f32, 0.1), contact.mSeparation, eps);
}

test "a sphere grows by its largest scale axis" {
    //scale 3 on y only: radius 0.5 * 3 = 1.5, plus the other's 0.5 is 2
    var stretched_transform = PlacedAt(.{ .x = 0, .y = 0, .z = 0 }, .{ .x = 1, .y = 3, .z = 1 });
    var stretched_collider = Sphere(0.5);
    var other_collider = Sphere(0.5);

    var contact = EmptyContact();
    //measured along x, not y, so the grow is even rather than along the scaled axis
    var near = PlacedAt(.{ .x = 1.9, .y = 0, .z = 0 }, ONE);
    try std.testing.expect(Collisions.TestShapes(&contact, &stretched_transform, &stretched_collider, &near, &other_collider));
    var far = PlacedAt(.{ .x = 2.1, .y = 0, .z = 0 }, ONE);
    try std.testing.expect(!Collisions.TestShapes(&contact, &stretched_transform, &stretched_collider, &far, &other_collider));
}

test "sphere against a box face" {
    //a default box spans 0.5 each way, so a radius 0.5 sphere touches it once its center is under 1 away
    var box_transform = PlacedAt(.{ .x = 0, .y = 0, .z = 0 }, ONE);
    var box_collider = Box(ONE);
    var sphere_collider = Sphere(0.5);

    var contact = EmptyContact();
    var near = PlacedAt(.{ .x = 0.9, .y = 0, .z = 0 }, ONE);
    try std.testing.expect(Collisions.TestShapes(&contact, &box_transform, &box_collider, &near, &sphere_collider));
    try std.testing.expectApproxEqAbs(@as(f32, -0.1), contact.mSeparation, eps);
    //box to sphere
    try std.testing.expectApproxEqAbs(@as(f32, 1), contact.mNormal.x, eps);

    //the same pair the other way round flips the normal and keeps the depth
    try std.testing.expect(Collisions.TestShapes(&contact, &near, &sphere_collider, &box_transform, &box_collider));
    try std.testing.expectApproxEqAbs(@as(f32, -0.1), contact.mSeparation, eps);
    try std.testing.expectApproxEqAbs(@as(f32, -1), contact.mNormal.x, eps);

    var touching = PlacedAt(.{ .x = 1.0, .y = 0, .z = 0 }, ONE);
    try std.testing.expect(!Collisions.TestShapes(&contact, &box_transform, &box_collider, &touching, &sphere_collider));
    var far = PlacedAt(.{ .x = 1.1, .y = 0, .z = 0 }, ONE);
    try std.testing.expect(!Collisions.TestShapes(&contact, &box_transform, &box_collider, &far, &sphere_collider));
    try std.testing.expectApproxEqAbs(@as(f32, 0.1), contact.mSeparation, eps);
}

test "sphere against a box corner is rounder than the box" {
    //0.4 past the corner on x and y is 0.566 from it: inside a box-vs-box test, but clear of a radius 0.5 sphere
    var box_transform = PlacedAt(.{ .x = 0, .y = 0, .z = 0 }, ONE);
    var box_collider = Box(ONE);
    var sphere_collider = Sphere(0.5);

    var contact = EmptyContact();
    var past_corner = PlacedAt(.{ .x = 0.9, .y = 0.9, .z = 0 }, ONE);
    try std.testing.expect(!Collisions.TestShapes(&contact, &box_transform, &box_collider, &past_corner, &sphere_collider));

    //0.3 past on both is 0.424 from the corner, so 0.076 deep along the diagonal
    var on_corner = PlacedAt(.{ .x = 0.8, .y = 0.8, .z = 0 }, ONE);
    try std.testing.expect(Collisions.TestShapes(&contact, &box_transform, &box_collider, &on_corner, &sphere_collider));
    const diagonal = @sqrt(0.5);
    try std.testing.expectApproxEqAbs(@as(f32, @sqrt(0.18) - 0.5), contact.mSeparation, eps);
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
    try std.testing.expect(Collisions.TestShapes(&contact, &box_transform, &box_collider, &inside, &sphere_collider));
    //out to the face, then the whole radius past it
    try std.testing.expectApproxEqAbs(@as(f32, -0.7), contact.mSeparation, eps);
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
    try std.testing.expect(Collisions.TestShapes(&contact, &box_transform, &box_collider, &near, &sphere_collider));
    try std.testing.expectApproxEqAbs(@as(f32, -0.1), contact.mSeparation, eps);
    try std.testing.expectApproxEqAbs(@as(f32, -1), contact.mNormal.y, eps);

    var far = PlacedAt(.{ .x = 0, .y = -3.1, .z = 0 }, .{ .x = 2, .y = 2, .z = 2 });
    try std.testing.expect(!Collisions.TestShapes(&contact, &box_transform, &box_collider, &far, &sphere_collider));
}

test "a sphere sees a box's rotation" {
    //a default box turned 45 degrees about z points a corner along +x, 0.707 out instead of the face's 0.5
    var box_transform = PlacedAt(.{ .x = 0, .y = 0, .z = 0 }, ONE);
    box_transform.SetWorldRotation(Quat(f32).FromAxisAngle(.{ .x = 0, .y = 0, .z = 1 }, std.math.pi / 4.0));
    var box_collider = Box(ONE);
    var sphere_collider = Sphere(0.5);

    //1.1 out would be 0.1 clear of the unturned box, but is into the corner of the turned one
    var contact = EmptyContact();
    var sphere_transform = PlacedAt(.{ .x = 1.1, .y = 0, .z = 0 }, ONE);
    try std.testing.expect(Collisions.TestShapes(&contact, &box_transform, &box_collider, &sphere_transform, &sphere_collider));
    try std.testing.expectApproxEqAbs(@as(f32, 1.1 - @sqrt(0.5) - 0.5), contact.mSeparation, eps);
    //straight out of the corner toward the sphere, back in world space
    try std.testing.expectApproxEqAbs(@as(f32, 1), contact.mNormal.x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 0), contact.mNormal.y, eps);
}
