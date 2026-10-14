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

//==================================colliders, when the editor shows them==================================

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const ColliderComponent = EntityComponents.ColliderComponent;
const TransformComponent = EntityComponents.TransformComponent;
const CameraView = @import("../../Renderer/Renderer.zig").CameraView;
const SDFFunc = @import("../../Math/SDFFunctions.zig");
const MathTypes = @import("../../Math/MathTypes.zig");
const Vec3 = MathTypes.Vec3;

const eps: f32 = 0.0001;

fn PlacedAt(position: Vec3(f32), scale: Vec3(f32)) TransformComponent {
    var transform: TransformComponent = .{};
    transform.SetWorldPosition(position);
    transform.SetWorldScale(scale);
    return transform;
}

/// A camera at the origin whose view is 1 unit tall at a distance of 1, drawn 100 pixels tall: a pixel is a hundredth
/// of the distance across
fn TestCamera(display_scale: f32) CameraView {
    return .{
        .Pose = .{ .Position = .{ .x = 0, .y = 0, .z = 0 }, .Rotation = .{ .w = 1, .x = 0, .y = 0, .z = 0 } },
        .TanHalfFov = 0.5,
        .TargetWidth = 100,
        .TargetHeight = 100,
        .FarDistance = 1000,
        .DisplayScale = display_scale,
    };
}

fn ExpectVec3(expected: Vec3(f32), actual: Vec3(f32)) !void {
    try std.testing.expectApproxEqAbs(expected.x, actual.x, eps);
    try std.testing.expectApproxEqAbs(expected.y, actual.y, eps);
    try std.testing.expectApproxEqAbs(expected.z, actual.z, eps);
}

test "a box collider is drawn as a see-through box the size physics tests, where its entity is" {
    const transform = PlacedAt(.{ .x = 1, .y = 2, .z = -10 }, .{ .x = 2, .y = 1, .z = 1 });
    const collider = ColliderComponent{ .mShape = .Box, .mBoxSize = .{ .x = 1, .y = 1, .z = 3 } };
    const drawn = Renderer2D.ColliderShape(&transform, &collider, null, TestCamera(1));
    try std.testing.expectEqual(.Box, drawn.Shape.Type);
    try std.testing.expect(drawn.Shape.Flags & Renderer2D.ShapeData.FLAG_TRANSPARENT != 0);
    try ExpectVec3(.{ .x = 1, .y = 0.5, .z = 1.5 }, Vec3(f32).FromArray(drawn.Shape.Size));
    try ExpectVec3(.{ .x = 1, .y = 2, .z = -10 }, SDFFunc.ShapeCenter(drawn.Shape));
}

test "a sphere collider is drawn as a sphere its radius grown by its largest scale axis" {
    const transform = PlacedAt(.{ .x = 0, .y = 0, .z = -10 }, .{ .x = 1, .y = 3, .z = 1 });
    const collider = ColliderComponent{ .mShape = .Sphere, .mRadius = 0.5 };
    const drawn = Renderer2D.ColliderShape(&transform, &collider, null, TestCamera(1));
    try std.testing.expectEqual(.Sphere, drawn.Shape.Type);
    try ExpectVec3(.{ .x = 1.5, .y = 1.5, .z = 1.5 }, Vec3(f32).FromArray(drawn.Shape.Size));
}

test "a collider's edge band is the same number of pixels wide on screen however far away it is" {
    const collider = ColliderComponent{ .mShape = .Box };
    const near = PlacedAt(.{ .x = 0, .y = 0, .z = -10 }, .{ .x = 1, .y = 1, .z = 1 });
    const far = PlacedAt(.{ .x = 0, .y = 0, .z = -20 }, .{ .x = 1, .y = 1, .z = 1 });
    //a pixel 10 away is 2 * 10 * 0.5 / 100 = 0.1 across
    const pixel_at_10: f32 = 0.1;
    try std.testing.expectApproxEqAbs(Renderer2D.COLLIDER_EDGE_PIXELS * pixel_at_10, Renderer2D.ColliderShape(&near, &collider, null, TestCamera(1)).EdgeWidth, eps);
    try std.testing.expectApproxEqAbs(Renderer2D.COLLIDER_EDGE_PIXELS * pixel_at_10 * 2, Renderer2D.ColliderShape(&far, &collider, null, TestCamera(1)).EdgeWidth, eps);
    //and wider on a display scaled up, the way the rest of the UI is
    try std.testing.expectApproxEqAbs(Renderer2D.COLLIDER_EDGE_PIXELS * pixel_at_10 * 2, Renderer2D.ColliderShape(&near, &collider, null, TestCamera(2)).EdgeWidth, eps);
}
