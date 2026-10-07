//! Aabb: the boxes a BVH is built from. No engine needed. Run with `zig build test`.
const std = @import("std");
const Aabb = @import("../../Math/Aabb.zig");
const Vec3 = @import("../../Math/MathTypes.zig").Vec3;

fn Box(min: Vec3(f32), max: Vec3(f32)) Aabb {
    return .{ .Min = min, .Max = max };
}

test "the union of two boxes holds both, and no more than it has to" {
    const a = Box(.{ .x = 0, .y = 0, .z = 0 }, .{ .x = 1, .y = 1, .z = 1 });
    const b = Box(.{ .x = 2, .y = -1, .z = 0.5 }, .{ .x = 3, .y = 0.5, .z = 4 });
    const both = a.Union(b);
    try std.testing.expectEqual(Vec3(f32){ .x = 0, .y = -1, .z = 0 }, both.Min);
    try std.testing.expectEqual(Vec3(f32){ .x = 3, .y = 1, .z = 4 }, both.Max);
}

test "the union with the empty box is the other box" {
    const a = Box(.{ .x = -2, .y = 3, .z = 1 }, .{ .x = 5, .y = 4, .z = 2 });
    try std.testing.expectEqual(a, Aabb.empty.Union(a));
    try std.testing.expectEqual(a, a.Union(Aabb.empty));
}

test "a box's center is half way between its corners" {
    const a = Box(.{ .x = -2, .y = 0, .z = 1 }, .{ .x = 4, .y = 2, .z = 1 });
    try std.testing.expectEqual(Vec3(f32){ .x = 1, .y = 1, .z = 1 }, a.Center());
}

test "a box contains what is inside it and on it, and nothing past it" {
    const a = Box(.{ .x = 0, .y = 0, .z = 0 }, .{ .x = 1, .y = 1, .z = 1 });
    try std.testing.expect(a.Contains(.{ .x = 0.5, .y = 0.5, .z = 0.5 }));
    try std.testing.expect(a.Contains(.{ .x = 1, .y = 0, .z = 1 }));
    try std.testing.expect(!a.Contains(.{ .x = 1.01, .y = 0.5, .z = 0.5 }));
    try std.testing.expect(!a.Contains(.{ .x = 0.5, .y = -0.01, .z = 0.5 }));
    try std.testing.expect(!Aabb.empty.Contains(.{ .x = 0, .y = 0, .z = 0 }));
}
