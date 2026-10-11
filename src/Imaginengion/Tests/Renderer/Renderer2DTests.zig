//! Renderer2D: what it leaves out of the shapes it draws. No engine needed. Run with `zig build test`.
const std = @import("std");
const Renderer2D = @import("../../Renderer/Renderer2D.zig");
const SurfaceComponent = @import("../../ECSComponents/Entity/SurfaceComponent.zig");

fn Surface(fill_alpha: f32, see_through: bool, border_width: f32, border_alpha: f32) SurfaceComponent {
    var surface = SurfaceComponent{};
    surface.mTexOptions.mColor.w = fill_alpha;
    surface.mTexOptions.mIsTransparent = see_through;
    surface.mBorderWidth = border_width;
    surface.mBorderColor.w = border_alpha;
    return surface;
}

test "a see-through quad with an invisible fill and no border draws nothing, whatever its texture" {
    try std.testing.expect(Renderer2D.QuadDrawsNothing(Surface(0, true, 0, 1)));
    //a border band that is itself invisible doesn't count
    try std.testing.expect(Renderer2D.QuadDrawsNothing(Surface(0, true, 2, 0)));
}

test "a quad with anything to see is still drawn" {
    //a faint fill
    try std.testing.expect(!Renderer2D.QuadDrawsNothing(Surface(0.01, true, 0, 1)));
    //an invisible fill with a border round it
    try std.testing.expect(!Renderer2D.QuadDrawsNothing(Surface(0, true, 2, 0.5)));
    //an ordinary opaque quad
    try std.testing.expect(!Renderer2D.QuadDrawsNothing(Surface(1, false, 0, 1)));
}

test "a quad that isn't see-through is drawn even with an invisible fill, since it hides what is behind it" {
    try std.testing.expect(!Renderer2D.QuadDrawsNothing(Surface(0, false, 0, 1)));
}
