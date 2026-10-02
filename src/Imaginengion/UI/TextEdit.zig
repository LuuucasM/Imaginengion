//! Editing text at a caret: the caret is a byte index into UTF-8 text that always sits at the start of a codepoint
//! (or at the end), so moving or deleting never splits a letter in half. Nothing here knows about entities or fonts:
//! the focus system (UI/FocusSystem.zig) uses it on a TextComponent's text.
const std = @import("std");

/// Where the caret goes one codepoint to the left. Stays put at the start
pub fn PrevBoundary(text: []const u8, caret: usize) usize {
    if (caret == 0) return 0;
    var index = @min(caret, text.len) - 1;
    //continuation bytes are 0b10xxxxxx: step back over them to the byte that starts the codepoint
    while (index > 0 and IsContinuation(text[index])) index -= 1;
    return index;
}

/// Where the caret goes one codepoint to the right. Stays put at the end
pub fn NextBoundary(text: []const u8, caret: usize) usize {
    if (caret >= text.len) return text.len;
    var index = caret + 1;
    while (index < text.len and IsContinuation(text[index])) index += 1;
    return index;
}

/// Puts `bytes` in at the caret and moves the caret past them
pub fn Insert(allocator: std.mem.Allocator, text: *std.ArrayList(u8), caret: *usize, bytes: []const u8) !void {
    try text.insertSlice(allocator, caret.*, bytes);
    caret.* += bytes.len;
}

/// Deletes the codepoint before the caret. Returns whether there was one
pub fn Backspace(text: *std.ArrayList(u8), caret: *usize) bool {
    if (caret.* == 0) return false;
    const start = PrevBoundary(text.items, caret.*);
    text.replaceRangeAssumeCapacity(start, caret.* - start, &.{});
    caret.* = start;
    return true;
}

/// Deletes the codepoint after the caret. Returns whether there was one
pub fn Delete(text: *std.ArrayList(u8), caret: usize) bool {
    if (caret >= text.items.len) return false;
    const end = NextBoundary(text.items, caret);
    text.replaceRangeAssumeCapacity(caret, end - caret, &.{});
    return true;
}

/// `bytes` with the line breaks taken out, for pasting into a single line: written into `out`, which must be at least
/// as long. Returns the part of `out` that was used
pub fn SingleLine(bytes: []const u8, out: []u8) []u8 {
    var len: usize = 0;
    for (bytes) |byte| {
        if (byte == '\n' or byte == '\r') continue;
        out[len] = byte;
        len += 1;
    }
    return out[0..len];
}

fn IsContinuation(byte: u8) bool {
    return byte & 0b1100_0000 == 0b1000_0000;
}
