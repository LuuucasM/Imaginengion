//! A set of collision layers (Physics/CollisionMask.zig): saved and read back, and whether two share a layer.
//! Run with `zig build test-engine`.
const std = @import("std");

const CollisionMask = @import("../../Physics/CollisionMask.zig");

test "a collision mask is saved and read back" {
    var mask: CollisionMask = .initOne(0);
    mask.set(2);
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    var write_stream: std.json.Stringify = .{ .writer = &out.writer };
    try write_stream.write(mask);

    const parsed = try std.json.parseFromSlice(CollisionMask, std.testing.allocator, out.written(), .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value.isSet(0) and parsed.value.isSet(2) and !parsed.value.isSet(1));
}

test "two masks intersect when they share a layer" {
    var a: CollisionMask = .initOne(3);
    try std.testing.expect(!a.intersects(.initOne(4)));
    a.set(4);
    try std.testing.expect(a.intersects(.initOne(4)));
    try std.testing.expect(!a.intersects(.empty));
    try std.testing.expect(a.intersects(.full));
}
