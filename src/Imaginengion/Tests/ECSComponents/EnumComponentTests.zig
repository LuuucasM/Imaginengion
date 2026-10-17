//! An enum value kept on an object (ECSComponents/Shared/EnumComponent.zig): read and set as the enum from the file,
//! another enum or a name the enum no longer has read as null, and saved by name and read back.
//! Run with `zig build test-engine`.
const std = @import("std");

const EnumComponent = @import("../../ECSComponents/Shared/EnumComponent.zig");

/// What GameState.zig would hold: the last part of its type's name is GameState, as @import("GameState").GameState's is
const GameState = enum { Playing, Paused, GameOver };
const Weather = enum { Sunny, Rain };

/// A component holding GameState's `value`, read from what a save would have, with no file (only the editor needs it)
fn Holding(value: []const u8) !EnumComponent {
    var text_buffer: [128]u8 = undefined;
    const text = try std.fmt.bufPrint(&text_buffer, "{{\"EnumFile\":null,\"Enum\":\"GameState\",\"Value\":\"{s}\"}}", .{value});
    const parsed = try std.json.parseFromSlice(EnumComponent, std.testing.allocator, text, .{});
    defer parsed.deinit();
    return parsed.value;
}

test "the value reads as the enum from its file, and sets from it" {
    var state = try Holding("Paused");
    try std.testing.expectEqual(GameState.Paused, state.Get(GameState).?);

    try state.Set(GameState.GameOver);
    try std.testing.expectEqualStrings("GameOver", state.GetName());
    try std.testing.expectEqual(GameState.GameOver, state.Get(GameState).?);
}

test "another enum, or a name the enum no longer has, reads as null and can't be set" {
    var state = try Holding("Paused");
    try std.testing.expectEqual(@as(?Weather, null), state.Get(Weather));
    try std.testing.expectError(error.WrongEnum, state.Set(Weather.Rain));
    try std.testing.expectEqualStrings("Paused", state.GetName());

    //renamed in the file since it was saved
    const renamed = try Holding("Pause");
    try std.testing.expectEqual(@as(?GameState, null), renamed.Get(GameState));

    //nothing picked yet
    const empty = try Holding("");
    try std.testing.expectEqual(@as(?GameState, null), empty.Get(GameState));
}

test "an enum value is saved by name and read back" {
    var state = try Holding("Playing");
    try state.Set(GameState.Paused);

    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    var write_stream: std.json.Stringify = .{ .writer = &out.writer };
    try write_stream.write(state);
    try std.testing.expectEqualStrings("{\"EnumFile\":null,\"Enum\":\"GameState\",\"Value\":\"Paused\"}", out.written());

    const parsed = try std.json.parseFromSlice(EnumComponent, std.testing.allocator, out.written(), .{});
    defer parsed.deinit();
    try std.testing.expectEqual(GameState.Paused, parsed.value.Get(GameState).?);
    try std.testing.expectEqualStrings("GameState", parsed.value.GetEnumName());
}
