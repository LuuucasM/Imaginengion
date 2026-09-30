const MathTypes = @import("MathTypes.zig");
const Vec2 = MathTypes.Vec2;

/// Where a render target is shown on screen, in window coordinates (the same space as the mouse).
pub const ScreenRect = struct {
    Min: Vec2(f32),
    Size: Vec2(f32),
    TargetSize: Vec2(f32), //the render target's size in pixels, which can differ from Size while it is stretched
};

/// The render target pixel under `screen_pos`, or null if it is outside the rect. Continuous like
/// CameraRay's pixels: the rect covers [Min, Min + Size), so its right and bottom edges are outside.
/// Scales by the target's own size rather than assuming it matches the rect, since a target
/// resized from last frame's panel size is shown stretched into this frame's rect.
pub fn ToTargetPixel(rect: ScreenRect, screen_pos: Vec2(f32)) ?Vec2(f32) {
    if (rect.Size.x <= 0 or rect.Size.y <= 0) return null;

    const local = screen_pos.SubVec(rect.Min);
    if (local.x < 0 or local.y < 0 or local.x >= rect.Size.x or local.y >= rect.Size.y) return null;

    return local.DivVec(rect.Size).MulVec(rect.TargetSize);
}

/// ToTargetPixel without the bounds check: a position outside the rect gives a pixel off the edge of the render
/// target, for something that has to keep following the mouse past the view it started in, like a drag. Null only
/// for a rect with no size
pub fn ToTargetPixelUnbounded(rect: ScreenRect, screen_pos: Vec2(f32)) ?Vec2(f32) {
    if (rect.Size.x <= 0 or rect.Size.y <= 0) return null;
    return screen_pos.SubVec(rect.Min).DivVec(rect.Size).MulVec(rect.TargetSize);
}
