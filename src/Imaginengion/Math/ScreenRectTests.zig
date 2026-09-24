const std = @import("std");
const MathTypes = @import("MathTypes.zig");
const ScreenRect = @import("ScreenRect.zig");
const Vec2 = MathTypes.Vec2;

const eps: f32 = 0.0001;

//a 400x300 image drawn at (50, 80) in the window, showing a target of the same size
const RECT = ScreenRect.ScreenRect{
    .Min = .{ .x = 50, .y = 80 },
    .Size = .{ .x = 400, .y = 300 },
    .TargetSize = .{ .x = 400, .y = 300 },
};

fn ExpectPixel(expected: Vec2(f32), actual: ?Vec2(f32)) !void {
    const pixel = actual orelse return error.TestExpectedPixel;
    try std.testing.expectApproxEqAbs(expected.x, pixel.x, eps);
    try std.testing.expectApproxEqAbs(expected.y, pixel.y, eps);
}

test "top left corner is pixel zero" {
    try ExpectPixel(.{ .x = 0, .y = 0 }, ScreenRect.ToTargetPixel(RECT, .{ .x = 50, .y = 80 }));
}

test "the rect's offset in the window is subtracted" {
    try ExpectPixel(.{ .x = 10.5, .y = 20.25 }, ScreenRect.ToTargetPixel(RECT, .{ .x = 60.5, .y = 100.25 }));
}

test "just inside the bottom right corner is just under the target size" {
    try ExpectPixel(.{ .x = 399.5, .y = 299.5 }, ScreenRect.ToTargetPixel(RECT, .{ .x = 449.5, .y = 379.5 }));
}

test "the right and bottom edges are outside" {
    try std.testing.expect(ScreenRect.ToTargetPixel(RECT, .{ .x = 450, .y = 100 }) == null);
    try std.testing.expect(ScreenRect.ToTargetPixel(RECT, .{ .x = 100, .y = 380 }) == null);
}

test "outside on every side" {
    try std.testing.expect(ScreenRect.ToTargetPixel(RECT, .{ .x = 49.9, .y = 100 }) == null);
    try std.testing.expect(ScreenRect.ToTargetPixel(RECT, .{ .x = 100, .y = 79.9 }) == null);
    try std.testing.expect(ScreenRect.ToTargetPixel(RECT, .{ .x = 500, .y = 100 }) == null);
    try std.testing.expect(ScreenRect.ToTargetPixel(RECT, .{ .x = 100, .y = 400 }) == null);
}

test "a stretched target maps to its own pixels" {
    //an 800x600 target squeezed into the 400x300 rect: every screen pixel covers two target pixels
    var stretched = RECT;
    stretched.TargetSize = .{ .x = 800, .y = 600 };
    try ExpectPixel(.{ .x = 200, .y = 100 }, ScreenRect.ToTargetPixel(stretched, .{ .x = 150, .y = 130 }));
}

test "a zero size rect never contains the mouse" {
    var empty = RECT;
    empty.Size = .{ .x = 0, .y = 300 };
    try std.testing.expect(ScreenRect.ToTargetPixel(empty, .{ .x = 50, .y = 100 }) == null);
    empty.Size = .{ .x = 400, .y = 0 };
    try std.testing.expect(ScreenRect.ToTargetPixel(empty, .{ .x = 100, .y = 80 }) == null);
}
