//! Reading an enum's value names out of its .zig file (ECSComponents/Asset/EnumAsset.zig): a plain enum, one with a tag
//! type and values, a non-exhaustive one, @"quoted" names, and the files it can't read.
//! Run with `zig build test-engine`.
const std = @import("std");

const EnumAsset = @import("../../../ECSComponents/Asset/EnumAsset.zig");

fn Names(arena: *std.heap.ArenaAllocator, source: [:0]const u8) EnumAsset.ParseError![]const []const u8 {
    return EnumAsset.ParseNames(arena.allocator(), source, "GameState");
}

fn ExpectNames(expected: []const []const u8, actual: []const []const u8) !void {
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |e, a| try std.testing.expectEqualStrings(e, a);
}

test "an enum's value names in the order they are written" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try ExpectNames(&.{ "Playing", "Paused", "GameOver" }, try Names(&arena,
        \\const std = @import("std");
        \\
        \\pub const GameState = enum { Playing, Paused, GameOver };
    ));

    //a tag type, values, doc comments, a declaration and a function inside it
    try ExpectNames(&.{ "Playing", "Paused" }, try Names(&arena,
        \\pub const GameState = enum(u8) {
        \\    /// in a match
        \\    Playing = 3,
        \\    Paused = 1,
        \\
        \\    pub const default: GameState = .Playing;
        \\    pub fn CanMove(self: GameState) bool {
        \\        return self == .Playing;
        \\    }
        \\};
    ));
}

test "a non-exhaustive enum's _ isn't a value, and a quoted name loses its quotes" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try ExpectNames(&.{ "Playing", "Game Over" }, try Names(&arena,
        \\pub const GameState = enum(u8) { Playing, @"Game Over", _ };
    ));
}

test "a file it can't read says why" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(error.SyntaxError, Names(&arena, "pub const GameState = enum { Playing, "));
    //named after another file, or not pub
    try std.testing.expectError(error.NoSuchEnum, Names(&arena, "pub const State = enum { Playing };"));
    try std.testing.expectError(error.NoSuchEnum, Names(&arena, "const GameState = enum { Playing };"));
    try std.testing.expectError(error.NotAnEnum, Names(&arena, "pub const GameState = struct { mPlaying: bool };"));
    //made at compile time, which only the compiler could work out
    try std.testing.expectError(error.NotAnEnum, Names(&arena, "pub const GameState = @import(\"std\").meta.FieldEnum(struct { a: u8 });"));
}
