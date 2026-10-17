//! A set of collision layers (Physics/CollisionMask.zig): saved as its bits' integer the way a plain bit set was, so
//! colliders saved before it existed load the same, and whether two share a layer.
//! Run with `zig build test-engine`.
const std = @import("std");

const CollisionMask = @import("../../Physics/CollisionMask.zig");
const ColliderComponent = @import("../../ECSComponents/EComponents.zig").ColliderComponent;

test "a collision mask is saved as its bits' integer and read back" {
    var mask: CollisionMask = .initOne(0);
    mask.set(2);
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    var write_stream: std.json.Stringify = .{ .writer = &out.writer };
    try write_stream.write(mask);
    try std.testing.expectEqualStrings("{\"mask\":5}", out.written());

    const parsed = try std.json.parseFromSlice(CollisionMask, std.testing.allocator, out.written(), .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value.isSet(0) and parsed.value.isSet(2) and !parsed.value.isSet(1));
}

test "a collider saved with plain bit sets loads its layers" {
    const saved =
        \\{"Shape":"Box","CollisionFilter":{"IsTrigger":false,"CategoryMask":{"mask":2},"RespondMask":{"mask":6}}}
    ;
    const parsed = try std.json.parseFromSlice(ColliderComponent, std.testing.allocator, saved, .{});
    defer parsed.deinit();
    const filter = parsed.value.mCollisionFilter;
    try std.testing.expect(filter.CategoryMask.isSet(1) and filter.CategoryMask.count() == 1);
    try std.testing.expect(filter.RespondMask.isSet(1) and filter.RespondMask.isSet(2) and filter.RespondMask.count() == 2);
}

test "two masks intersect when they share a layer" {
    var a: CollisionMask = .initOne(3);
    try std.testing.expect(!a.intersects(.initOne(4)));
    a.set(4);
    try std.testing.expect(a.intersects(.initOne(4)));
    try std.testing.expect(!a.intersects(.empty));
    try std.testing.expect(a.intersects(.full));
}
