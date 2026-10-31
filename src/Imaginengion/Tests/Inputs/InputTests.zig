const std = @import("std");
const InputManager = @import("../../Inputs/Input.zig");
const Vec2 = @import("../../Math/MathTypes.zig").Vec2;

test "pressing and releasing in place is a click" {
    var input: InputManager = .empty;

    input.SetMousePressed(.BUTTON_LEFT, .{ .x = 100, .y = 200 });
    try std.testing.expect(input.SetMouseReleased(.BUTTON_LEFT, .{ .x = 101, .y = 202 }));
}

test "moving past the threshold before releasing is a drag, not a click" {
    var input: InputManager = .empty;

    input.SetMousePressed(.BUTTON_LEFT, .{ .x = 100, .y = 200 });
    try std.testing.expect(!input.SetMouseReleased(.BUTTON_LEFT, .{ .x = 110, .y = 200 }));

    //right at the threshold counts as moved
    input.SetMousePressed(.BUTTON_LEFT, .{ .x = 100, .y = 200 });
    try std.testing.expect(!input.SetMouseReleased(.BUTTON_LEFT, .{ .x = 100 + InputManager.CLICK_DRAG_THRESHOLD, .y = 200 }));
}

test "a release without a press is not a click" {
    var input: InputManager = .empty;

    try std.testing.expect(!input.SetMouseReleased(.BUTTON_LEFT, .{ .x = 0, .y = 0 }));
}

test "each button is tracked on its own" {
    var input: InputManager = .empty;

    //left goes down here, right goes down far away, and each comes up where it went down
    input.SetMousePressed(.BUTTON_LEFT, .{ .x = 10, .y = 10 });
    input.SetMousePressed(.BUTTON_RIGHT, .{ .x = 500, .y = 500 });
    try std.testing.expect(input.SetMouseReleased(.BUTTON_RIGHT, .{ .x = 500, .y = 500 }));
    try std.testing.expect(input.SetMouseReleased(.BUTTON_LEFT, .{ .x = 10, .y = 10 }));
}

test "a click is only reported once" {
    var input: InputManager = .empty;

    input.SetMousePressed(.BUTTON_LEFT, .{ .x = 50, .y = 50 });
    try std.testing.expect(input.SetMouseReleased(.BUTTON_LEFT, .{ .x = 50, .y = 50 }));
    //a second release with no press in between is not another click
    try std.testing.expect(!input.SetMouseReleased(.BUTTON_LEFT, .{ .x = 50, .y = 50 }));
}

test "the pressed state still follows the button" {
    var input: InputManager = .empty;

    input.SetMousePressed(.BUTTON_MIDDLE, .{ .x = 0, .y = 0 });
    try std.testing.expect(input.IsMousePressed(.BUTTON_MIDDLE));
    _ = input.SetMouseReleased(.BUTTON_MIDDLE, .{ .x = 0, .y = 0 });
    try std.testing.expect(!input.IsMousePressed(.BUTTON_MIDDLE));
}

test "a key is pressed on its first press and repeated from its second" {
    var input: InputManager = .empty;

    input.SetKeyPressed(.A);
    try std.testing.expect(input.IsKeyPressed(.A));
    try std.testing.expect(!input.IsKeyRepeated(.A));

    input.SetKeyPressed(.A);
    try std.testing.expect(input.IsKeyPressed(.A));
    try std.testing.expect(input.IsKeyRepeated(.A));
}

test "releasing a repeating key clears both, so its next press is a fresh one" {
    var input: InputManager = .empty;

    input.SetKeyPressed(.A);
    input.SetKeyPressed(.A);
    input.SetKeyReleased(.A);
    try std.testing.expect(!input.IsKeyPressed(.A));
    try std.testing.expect(!input.IsKeyRepeated(.A));

    input.SetKeyPressed(.A);
    try std.testing.expect(input.IsKeyPressed(.A));
    try std.testing.expect(!input.IsKeyRepeated(.A));
}

test "keys are tracked on their own, including ones either side of a word boundary in the set" {
    var input: InputManager = .empty;

    //F6 and F7 are scan codes 63 and 64, which land in different words of the bit set
    input.SetKeyPressed(.F6);
    try std.testing.expect(input.IsKeyPressed(.F6));
    try std.testing.expect(!input.IsKeyPressed(.F7));

    input.SetKeyPressed(.ENDCALL);
    input.SetKeyPressed(.ENDCALL);
    try std.testing.expect(input.IsKeyRepeated(.ENDCALL));
    try std.testing.expect(!input.IsKeyRepeated(.F6));
}

test "a text input taking the keyboard hides keys from everything but the unfiltered read" {
    var input: InputManager = .empty;

    input.SetKeyPressed(.LCTRL);
    input.SetKeyPressed(.LCTRL);
    input.mKeyboardTaken = true;
    try std.testing.expect(!input.IsKeyPressed(.LCTRL));
    try std.testing.expect(!input.IsKeyRepeated(.LCTRL));
    try std.testing.expect(input.IsKeyPressedUnfiltered(.LCTRL));
}

test "mouse buttons repeat and clear the same way keys do" {
    var input: InputManager = .empty;

    input.SetMousePressed(.BUTTON_X2, .{ .x = 0, .y = 0 });
    try std.testing.expect(!input.IsMouseRepeated(.BUTTON_X2));
    input.SetMousePressed(.BUTTON_X2, .{ .x = 0, .y = 0 });
    try std.testing.expect(input.IsMouseRepeated(.BUTTON_X2));

    _ = input.SetMouseReleased(.BUTTON_X2, .{ .x = 0, .y = 0 });
    try std.testing.expect(!input.IsMousePressed(.BUTTON_X2));
    try std.testing.expect(!input.IsMouseRepeated(.BUTTON_X2));
}
