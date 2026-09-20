//! Unit tests for `SparseSet`. These live outside SparseSet.zig so the data structure
//! itself stays free of test-only code. Run with `zig build test`.
const std = @import("std");
const SparseSet = @import("SparseSet.zig").SparseSet;

const TrackedSet = SparseSet(u32, u20, u64, true);
const UntrackedSet = SparseSet(u32, u20, u64, false);

test "add, get and remove" {
    const allocator = std.testing.allocator;
    var set: UntrackedSet = .empty;
    defer set.Deinit(allocator);

    for (0..5) |i| _ = try set.AddValue(allocator, @intCast(i), i * 10);

    try std.testing.expect(set.HasSparse(3));
    try std.testing.expectEqual(@as(u64, 30), set.GetValueBySparse(3).*);

    set.Remove(3);

    try std.testing.expect(!set.HasSparse(3));
    //the swapped element is still reachable
    try std.testing.expectEqual(@as(u64, 40), set.GetValueBySparse(4).*);
    try std.testing.expectEqual(@as(u64, 0), set.GetValueBySparse(0).*);
}

test "untracked sets take new ids after a remove" {
    const allocator = std.testing.allocator;
    var set: UntrackedSet = .empty;
    defer set.Deinit(allocator);

    for (0..5) |i| _ = try set.AddValue(allocator, @intCast(i), i);
    set.Remove(2);

    _ = try set.AddValue(allocator, 7, 70);

    try std.testing.expect(set.HasSparse(7) and !set.HasSparse(2));
    try std.testing.expectEqual(@as(u64, 4), set.GetValueBySparse(4).*);
}

test "free ids come back newest first with a new generation" {
    const allocator = std.testing.allocator;
    var set: TrackedSet = .empty;
    defer set.Deinit(allocator);

    try std.testing.expect(set.AddValueToFreeID(0) == null);

    for (0..8) |i| _ = try set.AddValue(allocator, @intCast(i), i);
    for ([_]u32{ 1, 3, 4, 6 }) |entity_id| set.Remove(entity_id);
    try std.testing.expectEqual(@as(usize, 4), set.mFreeCount);

    //reusing and removing interleaved, which is where a single slot free list broke down
    var reused: [5]u32 = undefined;
    reused[0] = set.AddValueToFreeID(100).?;
    reused[1] = set.AddValueToFreeID(101).?;
    set.Remove(0);
    reused[2] = set.AddValueToFreeID(102).?;
    reused[3] = set.AddValueToFreeID(103).?;
    reused[4] = set.AddValueToFreeID(104).?;

    try std.testing.expect(set.AddValueToFreeID(0) == null);

    const expected_indices = [_]u32{ 6, 4, 0, 3, 1 };
    for (reused, expected_indices, 100..) |entity_id, expected_index, expected_value| {
        try std.testing.expectEqual(expected_index, @as(u32, TrackedSet.GetIndexFrom(entity_id)));
        try std.testing.expectEqual(@as(u12, 1), TrackedSet.GetGenFrom(entity_id));
        try std.testing.expectEqual(@as(u64, expected_value), set.GetValueBySparse(entity_id).*);
    }

    //the old generation of each reused id is dead
    for ([_]u32{ 0, 1, 3, 4, 6 }) |stale_id| try std.testing.expect(!set.HasSparse(stale_id));

    //untouched entries kept their values, and growth past capacity still works
    try std.testing.expectEqual(@as(u64, 2), set.GetValueBySparse(2).*);
    for (8..500) |i| _ = try set.AddValue(allocator, @intCast(i), i);
    try std.testing.expectEqual(@as(u64, 499), set.GetValueBySparse(499).*);

    //reusing the same index a second time moves to the next generation
    set.Remove(reused[0]);
    const reused_again = set.AddValueToFreeID(9).?;
    try std.testing.expectEqual(@as(u32, 6), @as(u32, TrackedSet.GetIndexFrom(reused_again)));
    try std.testing.expectEqual(@as(u12, 2), TrackedSet.GetGenFrom(reused_again));
}

test "clearAndFree resets the free list" {
    const allocator = std.testing.allocator;
    var set: TrackedSet = .empty;
    defer set.Deinit(allocator);

    for (0..4) |i| _ = try set.AddValue(allocator, @intCast(i), i);
    set.Remove(2);

    set.clearAndFree(allocator);

    try std.testing.expect(set.AddValueToFreeID(0) == null);
    _ = try set.AddValue(allocator, 0, 0);
    try std.testing.expect(set.HasSparse(0));
}

test "CopyInto reproduces the values and the free list" {
    const allocator = std.testing.allocator;
    var set: TrackedSet = .empty;
    defer set.Deinit(allocator);

    for (0..6) |i| _ = try set.AddValue(allocator, @intCast(i), i * 10);
    for ([_]u32{ 1, 4 }) |entity_id| set.Remove(entity_id);

    var copy: TrackedSet = .empty;
    defer copy.Deinit(allocator);
    try set.CopyInto(allocator, &copy);

    for ([_]u32{ 0, 2, 3, 5 }) |entity_id| {
        try std.testing.expect(copy.HasSparse(entity_id));
        try std.testing.expectEqual(set.GetValueBySparse(entity_id).*, copy.GetValueBySparse(entity_id).*);
    }
    for ([_]u32{ 1, 4 }) |entity_id| try std.testing.expect(!copy.HasSparse(entity_id));

    //both hand out the same free ids, in the same order
    try std.testing.expectEqual(@as(usize, 2), copy.mFreeCount);
    try std.testing.expectEqual(set.AddValueToFreeID(100).?, copy.AddValueToFreeID(100).?);
    try std.testing.expectEqual(set.AddValueToFreeID(101).?, copy.AddValueToFreeID(101).?);
    try std.testing.expect(copy.AddValueToFreeID(102) == null);

    //and they are separate sets from here on
    copy.Remove(0);
    try std.testing.expect(set.HasSparse(0) and !copy.HasSparse(0));
}

test "CopyInto of an empty set leaves an empty set" {
    const allocator = std.testing.allocator;
    var set: UntrackedSet = .empty;
    defer set.Deinit(allocator);

    var copy: UntrackedSet = .empty;
    defer copy.Deinit(allocator);
    try set.CopyInto(allocator, &copy);

    try std.testing.expect(!copy.HasSparse(0));
    _ = try copy.AddValue(allocator, 0, 7);
    try std.testing.expectEqual(@as(u64, 7), copy.GetValueBySparse(0).*);
}

test "generation wraps back to zero" {
    const max_generation: u32 = (1 << 12) - 1;
    const entity_id: u32 = (max_generation << 20) | 5;

    try std.testing.expectEqual(@as(u32, 5), TrackedSet.NextGeneration(entity_id));
}
