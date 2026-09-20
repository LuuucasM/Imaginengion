//! Unit tests for `StaticSkipField`. These live outside SkipField.zig so the data structure
//! itself stays free of test-only code. Run with `zig build test`.
const std = @import("std");
const StaticSkipField = @import("SkipField.zig").StaticSkipField;

test "Init Small Field" {
    const FieldSize = 1;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field: SkipFieldT = .AllSkip;
    try std.testing.expect(field.mSkipField[0] == FieldSize);

    field = .NoSkip;
    try std.testing.expect(field.mSkipField[0] == 0);
}

test "Small Change To UnSkip" {
    const FieldSize = 1;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field: SkipFieldT = .AllSkip;
    try std.testing.expect(field.mSkipField[0] == 1);

    field.ChangeToUnskipped(0);
    try std.testing.expect(field.mSkipField[0] == 0);
}

test "Small Change To Skip" {
    const FieldSize = 1;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field: SkipFieldT = .NoSkip;
    try std.testing.expect(field.mSkipField[0] == 0);

    field.ChangeToSkipped(0);
    try std.testing.expect(field.mSkipField[0] == 1);
}

test "Init Large Field" {
    const FieldSize = 10;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field: SkipFieldT = .AllSkip;
    try std.testing.expect(field.mSkipField[0] == FieldSize);
    try std.testing.expect(field.mSkipField[FieldSize - 1] == FieldSize);
    for (1..FieldSize - 2) |i| {
        try std.testing.expect(field.mSkipField[i] == 1);
    }

    field = .NoSkip;
    for (0..FieldSize) |i| {
        try std.testing.expect(field.mSkipField[i] == 0);
    }
}

test "Large Change To Skip" {
    const FieldSize = 5;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field: SkipFieldT = .NoSkip;

    field.ChangeToSkipped(4);
    try std.testing.expect(field.mSkipField[4] == 1);

    field.ChangeToSkipped(0);
    try std.testing.expect(field.mSkipField[0] == 1);

    field.ChangeToSkipped(3);
    try std.testing.expect(field.mSkipField[3] == 2);
    try std.testing.expect(field.mSkipField[4] == 2);

    field.ChangeToSkipped(1);
    try std.testing.expect(field.mSkipField[0] == 2);
    try std.testing.expect(field.mSkipField[1] == 2);

    field.ChangeToSkipped(2);
    try std.testing.expect(field.mSkipField[0] == 5);
    try std.testing.expect(field.mSkipField[4] == 5);
    try std.testing.expect(field.mSkipField[2] == 1);
}

test "Large Change To UnSkip" {
    const FieldSize = 5;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field: SkipFieldT = .AllSkip;

    field.ChangeToUnskipped(4);
    try std.testing.expect(field.mSkipField[0] == 4);
    try std.testing.expect(field.mSkipField[3] == 4);

    field.ChangeToUnskipped(0);
    try std.testing.expect(field.mSkipField[1] == 3);
    try std.testing.expect(field.mSkipField[3] == 3);

    field.ChangeToUnskipped(2);
    try std.testing.expect(field.mSkipField[1] == 1);
    try std.testing.expect(field.mSkipField[3] == 1);
}

fn ExpectIteration(field: anytype, expected: []const usize) !void {
    var mutable_field = field;
    var visited: [@TypeOf(field).SkipFieldSize]usize = undefined;
    var count: usize = 0;

    var iter = mutable_field.Iterator();
    while (iter.next()) |i| : (count += 1) {
        try std.testing.expect(count < expected.len); //otherwise it is visiting skipped indices
        visited[count] = i;
    }

    try std.testing.expectEqualSlices(usize, expected, visited[0..count]);
}

test "Iterating Skipfield: ends skipped" {
    const SkipFieldT = StaticSkipField(5);

    var field: SkipFieldT = .NoSkip;
    field.ChangeToSkipped(4);
    field.ChangeToSkipped(0);

    try ExpectIteration(field, &.{ 1, 2, 3 });
}

test "Iterating Skipfield: run at the end" {
    const SkipFieldT = StaticSkipField(5);

    var field: SkipFieldT = .NoSkip;
    field.ChangeToSkipped(4);
    field.ChangeToSkipped(3);

    try ExpectIteration(field, &.{ 0, 1, 2 });
}

test "Iterating Skipfield: run in the middle" {
    const SkipFieldT = StaticSkipField(5);

    var field: SkipFieldT = .NoSkip;
    field.ChangeToSkipped(2);
    field.ChangeToSkipped(3);

    try ExpectIteration(field, &.{ 0, 1, 4 });
}

test "Iterating Skipfield: last index unskipped does not run off the end" {
    const SkipFieldT = StaticSkipField(5);

    var field: SkipFieldT = .AllSkip;
    field.ChangeToUnskipped(4);

    try ExpectIteration(field, &.{4});
}

test "Iterating Skipfield: all unskipped and all skipped" {
    const SkipFieldT = StaticSkipField(4);

    const no_skip: SkipFieldT = .NoSkip;
    try ExpectIteration(no_skip, &.{ 0, 1, 2, 3 });

    const all_skip: SkipFieldT = .AllSkip;
    try ExpectIteration(all_skip, &.{});
}

test "mNumUnskipped tracks the field" {
    const FieldSize = 5;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field: SkipFieldT = .AllSkip;
    try std.testing.expectEqual(@as(usize, 0), field.mNumUnskipped);

    field.ChangeToUnskipped(2);
    field.ChangeToUnskipped(2); //already unskipped, must not count twice
    try std.testing.expectEqual(@as(usize, 1), field.mNumUnskipped);

    field.ChangeToSkipped(2);
    field.ChangeToSkipped(2); //already skipped, must not count twice
    try std.testing.expectEqual(@as(usize, 0), field.mNumUnskipped);

    field.Reset(.NoSkip);
    try std.testing.expectEqual(@as(usize, FieldSize), field.mNumUnskipped);

    field.Reset(.AllSkip);
    try std.testing.expectEqual(@as(usize, 0), field.mNumUnskipped);

    var small: StaticSkipField(1) = .AllSkip;
    small.ChangeToUnskipped(0);
    small.ChangeToUnskipped(0);
    try std.testing.expectEqual(@as(usize, 1), small.mNumUnskipped);
    small.ChangeToSkipped(0);
    try std.testing.expectEqual(@as(usize, 0), small.mNumUnskipped);
}

test "Test Zeros Mask" {
    const FieldSize = 5;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field: SkipFieldT = .AllSkip;
    var mask: SkipFieldT = .AllSkip;

    field.ChangeToUnskipped(1);
    mask.ChangeToUnskipped(1);

    try std.testing.expect(field.HasSameUnskipped(&mask));

    mask.ChangeToUnskipped(3);

    try std.testing.expect(!field.HasSameUnskipped(&mask));

    field.ChangeToUnskipped(3);

    try std.testing.expect(field.HasSameUnskipped(&mask));
}

test "Test Union" {
    const FieldSize = 5;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field: SkipFieldT = .AllSkip;
    var mask: SkipFieldT = .AllSkip;

    field.ChangeToUnskipped(1);
    mask.ChangeToUnskipped(1);

    field.Union(&mask);

    try std.testing.expect(field.IndexIsUnskipped(1));

    mask.ChangeToSkipped(1);

    field.Union(&mask);

    try std.testing.expect(!field.IndexIsUnskipped(1));
}

test "Test Intersection" {
    const FieldSize = 5;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field: SkipFieldT = .AllSkip;
    var mask: SkipFieldT = .AllSkip;

    field.ChangeToUnskipped(1);
    mask.ChangeToUnskipped(2);

    field.Intersect(&mask);

    try std.testing.expect(field.IndexIsUnskipped(1));
    try std.testing.expect(field.IndexIsUnskipped(2));

    field.ChangeToUnskipped(3);

    field.Intersect(&mask);

    try std.testing.expect(field.IndexIsUnskipped(3));
}

test "Test Difference" {
    const FieldSize = 5;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field: SkipFieldT = .AllSkip;
    var mask: SkipFieldT = .AllSkip;

    field.ChangeToUnskipped(1);
    mask.ChangeToUnskipped(1);

    field.Difference(&mask);

    try std.testing.expect(!field.IndexIsUnskipped(1));
}

test "IsUnskippedSuperSet" {
    const FieldSize = 5;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field: SkipFieldT = .AllSkip;
    var mask: SkipFieldT = .AllSkip;

    try std.testing.expect(field.IsUnskippedSuperSet(&mask));

    field.ChangeToUnskipped(1);
    mask.ChangeToUnskipped(1);

    try std.testing.expect(field.IsUnskippedSuperSet(&mask));

    mask.ChangeToUnskipped(2);

    try std.testing.expect(!field.IsUnskippedSuperSet(&mask));

    field.ChangeToUnskipped(2);

    try std.testing.expect(field.IsUnskippedSuperSet(&mask));
}

test "IsAllUnskipped" {
    const FieldSize = 3;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field: SkipFieldT = .AllSkip;

    try std.testing.expect(field.IsAllUnskipped() == false);

    field.ChangeToUnskipped(0);
    field.ChangeToUnskipped(1);
    field.ChangeToUnskipped(2);

    try std.testing.expect(field.IsAllUnskipped() == true);

    field.ChangeToSkipped(1);

    try std.testing.expect(field.IsAllUnskipped() == false);
}

test "GetFirstUnskipped" {
    const FieldSize = 5;
    const SkipFieldT = StaticSkipField(FieldSize);

    var field: SkipFieldT = .AllSkip;

    field.ChangeToUnskipped(3);

    try std.testing.expect(field.GetFirstUnskipped() == 3);

    field.ChangeToUnskipped(4);

    try std.testing.expect(field.GetFirstUnskipped() == 3);

    field.ChangeToUnskipped(1);

    try std.testing.expect(field.GetFirstUnskipped() == 1);
}
