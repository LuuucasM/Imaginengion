const std = @import("std");
const InputManager = @import("Input.zig");
const Vec2 = @import("../Math/MathTypes.zig").Vec2;

fn NewInput() !InputManager {
    var input: InputManager = .empty;
    try input.Init(std.testing.allocator);
    return input;
}

test "pressing and releasing in place is a click" {
    var input = try NewInput();
    defer input.Deinit(std.testing.allocator);

    try input.SetMousePressed(.BUTTON_LEFT, .{ .x = 100, .y = 200 });
    try std.testing.expect(input.SetMouseReleased(.BUTTON_LEFT, .{ .x = 101, .y = 202 }));
}

test "moving past the threshold before releasing is a drag, not a click" {
    var input = try NewInput();
    defer input.Deinit(std.testing.allocator);

    try input.SetMousePressed(.BUTTON_LEFT, .{ .x = 100, .y = 200 });
    try std.testing.expect(!input.SetMouseReleased(.BUTTON_LEFT, .{ .x = 110, .y = 200 }));

    //right at the threshold counts as moved
    try input.SetMousePressed(.BUTTON_LEFT, .{ .x = 100, .y = 200 });
    try std.testing.expect(!input.SetMouseReleased(.BUTTON_LEFT, .{ .x = 100 + InputManager.CLICK_DRAG_THRESHOLD, .y = 200 }));
}

test "a release without a press is not a click" {
    var input = try NewInput();
    defer input.Deinit(std.testing.allocator);

    try std.testing.expect(!input.SetMouseReleased(.BUTTON_LEFT, .{ .x = 0, .y = 0 }));
}

test "each button is tracked on its own" {
    var input = try NewInput();
    defer input.Deinit(std.testing.allocator);

    //left goes down here, right goes down far away, and each comes up where it went down
    try input.SetMousePressed(.BUTTON_LEFT, .{ .x = 10, .y = 10 });
    try input.SetMousePressed(.BUTTON_RIGHT, .{ .x = 500, .y = 500 });
    try std.testing.expect(input.SetMouseReleased(.BUTTON_RIGHT, .{ .x = 500, .y = 500 }));
    try std.testing.expect(input.SetMouseReleased(.BUTTON_LEFT, .{ .x = 10, .y = 10 }));
}

test "a click is only reported once" {
    var input = try NewInput();
    defer input.Deinit(std.testing.allocator);

    try input.SetMousePressed(.BUTTON_LEFT, .{ .x = 50, .y = 50 });
    try std.testing.expect(input.SetMouseReleased(.BUTTON_LEFT, .{ .x = 50, .y = 50 }));
    //a second release with no press in between is not another click
    try std.testing.expect(!input.SetMouseReleased(.BUTTON_LEFT, .{ .x = 50, .y = 50 }));
}

test "the pressed state still follows the button" {
    var input = try NewInput();
    defer input.Deinit(std.testing.allocator);

    try input.SetMousePressed(.BUTTON_MIDDLE, .{ .x = 0, .y = 0 });
    try std.testing.expect(input.IsMousePressed(.BUTTON_MIDDLE));
    _ = input.SetMouseReleased(.BUTTON_MIDDLE, .{ .x = 0, .y = 0 });
    try std.testing.expect(!input.IsMousePressed(.BUTTON_MIDDLE));
}
