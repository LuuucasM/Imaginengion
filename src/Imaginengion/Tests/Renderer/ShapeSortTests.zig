//! ShapeSort: the order shapes are uploaded in. No engine needed. Run with `zig build test`.
const std = @import("std");
const ShapeSort = @import("../../Renderer/ShapeSort.zig");
const ShapeSortKey = ShapeSort.ShapeSortKey;
const SortEntry = ShapeSort.SortEntry;

/// Entries for `keys`, each at the index it was added at
fn Entries(comptime keys: []const ShapeSortKey) [keys.len]SortEntry {
    var entries: [keys.len]SortEntry = undefined;
    for (keys, 0..) |key, i| entries[i] = .{ .Key = key, .Index = @intCast(i) };
    return entries;
}

/// The added-at indices of sorted entries, the order the shapes come out in
fn Order(entries: []const SortEntry, out: []u32) []u32 {
    for (entries, out[0..entries.len]) |entry, *index| index.* = entry.Index;
    return out[0..entries.len];
}

test "the key compares path first, then group, then order" {
    //the fields' places in the u64: path is the top bit, group the 31 under it, order the bottom 32
    try std.testing.expectEqual(@as(u64, 1) << 63, (ShapeSortKey{ .Path = .Marched }).Value());
    try std.testing.expectEqual(@as(u64, 5) << 32, (ShapeSortKey{ .Group = 5 }).Value());
    try std.testing.expectEqual(@as(u64, 7), (ShapeSortKey{ .Order = 7 }).Value());
    try std.testing.expectEqual(@as(u64, 0), (ShapeSortKey{}).Value());
}

test "every direct shape comes before every marched one, whichever was added first" {
    var entries = Entries(&.{
        .{ .Path = .Marched },
        .{ .Path = .Direct, .Order = std.math.maxInt(u32) },
        .{ .Path = .Marched, .Group = 1 },
        .{ .Path = .Direct },
    });
    ShapeSort.Sort(&entries);
    var buf: [4]u32 = undefined;
    try std.testing.expectEqualSlices(u32, &.{ 3, 1, 0, 2 }, Order(&entries, &buf));
}

test "a group's shapes end up in one run, in their order within it" {
    var entries = Entries(&.{
        .{ .Path = .Marched, .Group = 2, .Order = 1 },
        .{ .Path = .Marched, .Group = 1, .Order = 1 },
        .{ .Path = .Marched, .Group = 2, .Order = 0 },
        .{ .Path = .Marched, .Group = 1, .Order = 0 },
    });
    ShapeSort.Sort(&entries);
    var buf: [4]u32 = undefined;
    try std.testing.expectEqualSlices(u32, &.{ 3, 1, 2, 0 }, Order(&entries, &buf));
}

test "shapes with the same key keep the order they were added in" {
    //all zero, today's keys: the sorted order is the order they were drawn in. Enough of them that the sort's own
    //order for equal elements would show if the added-at index didn't settle ties
    var entries: [64]SortEntry = undefined;
    for (&entries, 0..) |*entry, i| entry.* = .{ .Key = .{}, .Index = @intCast(i) };
    var prng = std.Random.DefaultPrng.init(0x7135);
    prng.random().shuffle(SortEntry, &entries);
    ShapeSort.Sort(&entries);
    for (entries, 0..) |entry, i| try std.testing.expectEqual(@as(u32, @intCast(i)), entry.Index);
}

test "the same shapes sort the same way every time, whatever order the sort is handed them in" {
    const keys = [_]ShapeSortKey{
        .{ .Order = 3 }, .{}, .{ .Path = .Marched }, .{ .Order = 3 }, .{}, .{ .Group = 1 }, .{ .Order = 1 },
    };
    var first = Entries(&keys);
    ShapeSort.Sort(&first);

    //the same entries, shuffled
    var second = Entries(&keys);
    var prng = std.Random.DefaultPrng.init(0x5047);
    prng.random().shuffle(SortEntry, &second);
    ShapeSort.Sort(&second);

    var first_buf: [keys.len]u32 = undefined;
    var second_buf: [keys.len]u32 = undefined;
    try std.testing.expectEqualSlices(u32, Order(&first, &first_buf), Order(&second, &second_buf));
}

test "gather puts the items in the sorted order" {
    const items = [_]u8{ 'a', 'b', 'c' };
    var entries = Entries(&.{ .{ .Order = 2 }, .{ .Order = 0 }, .{ .Order = 1 } });
    ShapeSort.Sort(&entries);
    var out: [3]u8 = undefined;
    ShapeSort.Gather(u8, &items, &entries, &out);
    try std.testing.expectEqualSlices(u8, "bca", &out);
}
