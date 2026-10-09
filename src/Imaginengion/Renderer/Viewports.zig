//! Quads that show a player's view (ViewportComponent): what they sample, the size the player renders at, which is
//! the quad's size on screen in pixels, so the view is never stretched, and the pixel of the view a ray through the
//! quad lands on, for picking through it.
const std = @import("std");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const CameraView = @import("Renderer.zig").CameraView;
const OverlayCanvas = @import("../Math/OverlayCanvas.zig");
const ShapeGeometry = @import("ShapeGeometry.zig");
const Ray = @import("../Math/CameraRay.zig").Ray;
const MathTypes = @import("../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;
const TransformComponent = EntityComponents.TransformComponent;

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const ViewpointComponent = EntityComponents.ViewpointComponent;
const EntitySceneComponent = EntityComponents.EntitySceneComponent;
const ViewportComponent = EntityComponents.ViewportComponent;
const SceneComponent = @import("../ECSComponents/SComponents.zig").SceneComponent;
const RenderTargetComponent = @import("../ECSComponents/PComponents.zig").RenderTargetComponent;

/// A width and height in pixels
pub const PixelSize = struct {
    Width: usize,
    Height: usize,
};

/// What a viewport quad samples: its player's render target, by the slot it is copied into. Null if the player has no
/// render target to show yet
pub fn ShownTarget(engine_context: *EngineContext, viewport: ViewportComponent) !?RenderTargetComponent.Shown {
    const zone = Tracy.ZoneInit("Viewports::ShownTarget", @src());
    defer zone.Deinit();
    if (!viewport.mPlayer.IsActive()) return null;
    const target = viewport.mPlayer.GetComponent(RenderTargetComponent) orelse return null;
    return try target.ShownSlot(engine_context);
}

/// How many pixels an overlay viewport quad covers when its scene is seen through `camera_view`: its laid out size in
/// canvas units, times the pixels a canvas unit covers. Null for one with no quad, or not in an overlay
pub fn PixelSizeOf(entity: Entity, camera_view: CameraView) ?PixelSize {
    const quad = ShapeGeometry.QuadOf(entity) orelse return null;
    if (entity.GetLayer() != .OverlayLayer) return null;
    const pixels_per_unit = entity.mManager.OverlayPixelsPerUnit(camera_view.TargetHeight, camera_view.DisplayScale);
    return .{
        .Width = @intFromFloat(@max(@round(quad.Size.x * pixels_per_unit), 0)),
        .Height = @intFromFloat(@max(@round(quad.Size.y * pixels_per_unit), 0)),
    };
}

/// Whether a pixel has to be on the view, or can be off its edges
pub const Bounds = enum {
    /// on the view only: what the pointer is over
    OnView,
    /// anywhere on the quad's plane: a drag that has left the view keeps following the pointer through it
    Unbounded,
};

/// The pixel of a viewport quad's player view that `ray` (a ray of `camera_view`, the view the quad is seen in) lands
/// on: continuous, from the view's top left, in the player viewpoint's pixels, the ones its own rays are made from
/// (Renderer.CameraView.PixelRay). Null if the ray misses the quad's plane, or misses the view when it must be on it.
/// Overlay quads only for now: a game layer one, a monitor in the world, has none
pub fn ViewPixelOnRay(entity: Entity, ray: Ray, camera_view: CameraView, bounds: Bounds) ?Vec2(f32) {
    const viewport = entity.GetComponent(ViewportComponent) orelse return null;
    if (!viewport.mPlayer.IsActive()) return null;
    const render_view = viewport.mPlayer.GetRenderView() orelse return null;
    const view_size = Vec2(f32){
        .x = @floatFromInt(render_view.mViewpoint.mViewportWidth),
        .y = @floatFromInt(render_view.mViewpoint.mViewportHeight),
    };
    return QuadPixelOnRay(entity, ray, camera_view, view_size, bounds);
}

/// Where `ray` lands on an overlay quad, as a pixel of a picture `picture_size` big stretched over the quad: from its
/// top left, x to the right and y down. Null if the ray misses the quad's plane, or misses the quad when it must be on it
pub fn QuadPixelOnRay(entity: Entity, ray: Ray, camera_view: CameraView, picture_size: Vec2(f32), bounds: Bounds) ?Vec2(f32) {
    const quad = ShapeGeometry.QuadOf(entity) orelse return null;
    if (entity.GetLayer() != .OverlayLayer or quad.Size.x <= 0 or quad.Size.y <= 0) return null;

    //onto the canvas, then into the quad's own space, which is what its size is in
    const point = ShapeGeometry.WorldCanvas(entity.mManager, camera_view).RayToCanvasPoint(ray) orelse return null;
    const transform = entity.GetComponent(TransformComponent).?;
    const scale = transform.GetWorldScale();
    if (scale.x == 0 or scale.y == 0) return null;
    const local = point.SubVec(transform.GetWorldPosition()).InvQuatRotate(transform.GetWorldRotation());

    //0 to 1 across the quad, left to right and top to bottom: canvas y is up, a picture's pixels run down
    const u = local.x / scale.x / quad.Size.x + 0.5;
    const v = 0.5 - local.y / scale.y / quad.Size.y;
    if (bounds == .OnView and (u < 0 or u > 1 or v < 0 or v > 1)) return null;
    return .{ .x = u * picture_size.x, .y = v * picture_size.y };
}

/// Sizes a viewport quad's player to the pixels the quad covers when seen through `camera_view`: its render target and
/// its viewpoint, which the ray math reads. Nothing happens for a quad with no size yet, which has nothing to show
pub fn FitPlayerToQuad(engine_context: *EngineContext, entity: Entity, camera_view: CameraView) !void {
    const zone = Tracy.ZoneInit("Viewports::FitPlayerToQuad", @src());
    defer zone.Deinit();
    const viewport = entity.GetComponent(ViewportComponent) orelse return;
    const size = PixelSizeOf(entity, camera_view) orelse return;
    if (size.Width < 1 or size.Height < 1 or !viewport.mPlayer.IsActive()) return;
    const render_view = viewport.mPlayer.GetRenderView() orelse return;
    render_view.mViewpoint.SetViewportSize(size.Width, size.Height);
    try render_view.mRenderTarget.mComputeTexture.Resize(engine_context, size.Width, size.Height);
}
