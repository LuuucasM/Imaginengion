//! Editing text at a caret (UI/TextEdit.zig): the caret only ever sits between whole codepoints. Standalone, run with
//! `zig build test`.
const std = @import("std");
const TextEdit = @import("../../UI/TextEdit.zig");

//"a", then 가 (3 bytes), then "b": byte offsets 0, 1, 4, 5
const MIXED = "a\xea\xb0\x80b";

test "the caret steps over a whole codepoint each way, and stops at the ends" {
    try std.testing.expectEqual(@as(usize, 1), TextEdit.NextBoundary(MIXED, 0));
    try std.testing.expectEqual(@as(usize, 4), TextEdit.NextBoundary(MIXED, 1));
    try std.testing.expectEqual(@as(usize, 5), TextEdit.NextBoundary(MIXED, 4));
    try std.testing.expectEqual(@as(usize, 5), TextEdit.NextBoundary(MIXED, 5));

    try std.testing.expectEqual(@as(usize, 4), TextEdit.PrevBoundary(MIXED, 5));
    try std.testing.expectEqual(@as(usize, 1), TextEdit.PrevBoundary(MIXED, 4));
    try std.testing.expectEqual(@as(usize, 0), TextEdit.PrevBoundary(MIXED, 1));
    try std.testing.expectEqual(@as(usize, 0), TextEdit.PrevBoundary(MIXED, 0));
}

test "typing goes in at the caret and moves it along" {
    const allocator = std.testing.allocator;
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(allocator);
    try text.appendSlice(allocator, "Plyer");

    var caret: usize = 2;
    try TextEdit.Insert(allocator, &text, &caret, "a");
    try std.testing.expectEqualStrings("Player", text.items);
    try std.testing.expectEqual(@as(usize, 3), caret);

    caret = text.items.len;
    try TextEdit.Insert(allocator, &text, &caret, " One");
    try std.testing.expectEqualStrings("Player One", text.items);
    try std.testing.expectEqual(text.items.len, caret);
}

test "backspace and delete take out a whole codepoint, and do nothing at the ends" {
    const allocator = std.testing.allocator;
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(allocator);
    try text.appendSlice(allocator, MIXED);

    //after 가: backspace takes all three of its bytes
    var caret: usize = 4;
    try std.testing.expect(TextEdit.Backspace(&text, &caret));
    try std.testing.expectEqualStrings("ab", text.items);
    try std.testing.expectEqual(@as(usize, 1), caret);

    try text.insertSlice(allocator, 1, "\xea\xb0\x80");
    //before 가: delete takes it, the caret stays
    try std.testing.expect(TextEdit.Delete(&text, caret));
    try std.testing.expectEqualStrings("ab", text.items);
    try std.testing.expectEqual(@as(usize, 1), caret);

    caret = 0;
    try std.testing.expect(!TextEdit.Backspace(&text, &caret));
    try std.testing.expect(!TextEdit.Delete(&text, text.items.len));
    try std.testing.expectEqualStrings("ab", text.items);
}

test "pasted line breaks are taken out, in place" {
    var bytes = "two\r\nlines\n".*;
    try std.testing.expectEqualStrings("twolines", TextEdit.SingleLine(&bytes, &bytes));
}
