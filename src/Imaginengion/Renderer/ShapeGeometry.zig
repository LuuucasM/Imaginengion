//! Where each shape actually is in the world, for a given camera. The one place that answers it, so
//! the renderer drawing a shape and picking clicking on it can never disagree, the same reason rays
//! (CameraRay) and text layout (TextLayout) each have a single home.
const std = @import("std");
const MathTypes = @import("../Math/MathTypes.zig");
const Vec3 = MathTypes.Vec3;
const Quat = MathTypes.Quat;

const OverlayCanvas = @import("../Math/OverlayCanvas.zig");
const CanvasTransform = OverlayCanvas.CanvasTransform;
const THICKNESS_2D = @import("../Math/SDFFunctions.zig").THICKNESS_2D;
const CameraView = @import("Renderer.zig").CameraView;
const TextLayout = @import("TextLayout.zig");

const Entity = @import("../ECSObjects/Entity.zig");
const EntityComponents = @import("../ECSComponents/EComponents.zig");
const TransformComponent = EntityComponents.TransformComponent;
const QuadComponent = EntityComponents.QuadComponent;
const TextComponent = EntityComponents.TextComponent;
const ColliderComponent = EntityComponents.ColliderComponent;
const EntitySceneComponent = EntityComponents.EntitySceneComponent;
const SceneComponent = @import("../ECSComponents/SComponents.zig").SceneComponent;

/// An oriented box in world space, what the renderer uploads and what a ray is tested against.
pub const Box = struct {
    Center: Vec3(f32),
    Rotation: Quat(f32),
    HalfExtents: Vec3(f32),
};

/// For an overlay entity, its scene's canvas in front of this camera: its transform is in canvas
/// units and this is what places it in the world. Null for a game layer entity, whose transform is
/// already world space.
pub fn EntityCanvas(entity: Entity, camera_view: CameraView) ?CanvasTransform {
    const entity_scene_comp = entity.GetComponent(EntitySceneComponent).?;
    const scene_component = entity_scene_comp.mScene.GetComponent(SceneComponent).?;

    return switch (scene_component.mLayerType) {
        .GameLayer => null,
        .OverlayLayer => OverlayCanvas.ComputeCanvasTransform(
            camera_view.Pose,
            camera_view.TanHalfFov,
            camera_view.TargetHeight,
            scene_component.GetPixelsPerUnit(camera_view.TargetHeight, camera_view.DisplayScale),
        ),
    };
}

/// The quad's own size grown by its scale (and everything above it in the hierarchy), placed by the
/// canvas for an overlay quad. Thickness stays THICKNESS_2D in world units either way.
pub fn QuadBox(transform: *const TransformComponent, quad: *const QuadComponent, canvas: ?CanvasTransform) Box {
    const world_scale = transform.GetWorldScale();
    var center = transform.GetWorldPosition();
    var rotation = transform.GetWorldRotation();
    var half_x = quad.mSize.x * world_scale.x * 0.5;
    var half_y = quad.mSize.y * world_scale.y * 0.5;

    if (canvas) |c| {
        center = c.ToWorldPoint(center);
        rotation = c.ToWorldRotation(rotation);
        half_x *= c.Scale;
        half_y *= c.Scale;
    }

    return .{
        .Center = center,
        .Rotation = rotation,
        .HalfExtents = .{ .x = half_x, .y = half_y, .z = THICKNESS_2D },
    };
}

/// What TextLayout needs for a text component, with its scale already applied. Text only grows evenly,
/// so it takes the largest scale axis, like a sphere collider. The font size and the bounds grow
/// together, which keeps the wrapping on the same words at any scale.
pub const TextParams = struct {
    FontSize: f32,
    LeftBound: f32, //how far the text runs left of its transform; layout lines start at x = 0, so they shift left by this
    RightBound: f32,
    WrapWidth: f32,
};

pub fn GetTextParams(transform: *const TransformComponent, text: *const TextComponent) TextParams {
    const world_scale = transform.GetWorldScale();
    const text_scale = @max(world_scale.x, @max(world_scale.y, world_scale.z));
    const left = text.mBounds.x * text_scale;
    const right = text.mBounds.y * text_scale;
    return .{
        .FontSize = text.mFontSize * text_scale,
        .LeftBound = left,
        .RightBound = right,
        .WrapWidth = left + right,
    };
}

/// The whole text area: across the full left to right bounds, and from the first line's ascender down
/// to the last line's descender, since the bounds say nothing about height. Placed by the text's own
/// transform, then by the canvas for overlay text. Generic over the font like TextLayout, so a test
/// can measure with a stand in; the engine always passes TextAsset.
pub fn TextBox(comptime FontT: type, transform: *const TransformComponent, text: *const TextComponent, font: *const FontT, canvas: ?CanvasTransform) Box {
    const params = GetTextParams(transform, text);
    const metrics = TextLayout.Measure(FontT, text.mText.items, font, params.FontSize, params.WrapWidth);

    //in the text's own space: x from -left to +right around the transform, y over the laid out lines
    const local_center = Vec3(f32){
        .x = (params.RightBound - params.LeftBound) * 0.5,
        .y = (metrics.Min.y + metrics.Max.y) * 0.5,
        .z = 0,
    };
    var half_x = (params.LeftBound + params.RightBound) * 0.5;
    var half_y = (metrics.Max.y - metrics.Min.y) * 0.5;

    const text_rotation = transform.GetWorldRotation();
    var center = transform.GetWorldPosition().AddVec(local_center.QuatRotate(text_rotation));
    var rotation = text_rotation;

    if (canvas) |c| {
        center = c.ToWorldPoint(center);
        rotation = c.ToWorldRotation(rotation);
        half_x *= c.Scale;
        half_y *= c.Scale;
    }

    return .{
        .Center = center,
        .Rotation = rotation,
        .HalfExtents = .{ .x = half_x, .y = half_y, .z = THICKNESS_2D },
    };
}

/// A box collider: its own size grown by its scale, in its entity's real rotation (rays test the rotated
/// box, even though the physics BoxBox test doesn't turn boxes yet). Placed by the canvas for an overlay
/// entity, the same as its visuals.
pub fn ColliderBox(transform: *const TransformComponent, collider: *const ColliderComponent, canvas: ?CanvasTransform) Box {
    var center = transform.GetWorldPosition();
    var rotation = transform.GetWorldRotation();
    var half_extents = collider.GetWorldHalfExtents(transform.GetWorldScale());

    if (canvas) |c| {
        center = c.ToWorldPoint(center);
        rotation = c.ToWorldRotation(rotation);
        half_extents = c.ToWorldVector(half_extents);
    }

    return .{ .Center = center, .Rotation = rotation, .HalfExtents = half_extents };
}

pub const Sphere = struct {
    Center: Vec3(f32),
    Radius: f32,
};

/// A sphere collider: its radius grown by its largest scale axis, placed by the canvas for an overlay entity.
pub fn ColliderSphere(transform: *const TransformComponent, collider: *const ColliderComponent, canvas: ?CanvasTransform) Sphere {
    var center = transform.GetWorldPosition();
    var radius = collider.GetWorldRadius(transform.GetWorldScale());

    if (canvas) |c| {
        center = c.ToWorldPoint(center);
        radius *= c.Scale;
    }

    return .{ .Center = center, .Radius = radius };
}
