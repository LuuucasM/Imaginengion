const std = @import("std");
const Collisions = @import("Collisions.zig");
const EntityComponents = @import("../ECSComponents/EComponents.zig");
const ColliderComponent = EntityComponents.ColliderComponent;
const TransformComponent = EntityComponents.TransformComponent;
const Vec3 = @import("../Math/MathTypes.zig").Vec3;

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
