//! Overlay scenes are parented to the camera: their entities are authored in canvas units (x right
//! and y up from the screen center, z toward the camera, the canvas plane at z = 0), and every frame
//! the canvas is placed in front of whichever camera is looking. The overlay pass then traces it with
//! that same camera, like the game layer.
//!
//! Where the canvas sits and how big a canvas unit is are what make it screen relative: at a fixed
//! distance in front of the camera, a canvas unit is sized from the camera's current fov so it always
//! covers the same number of pixels. Moving, turning or zooming the camera never moves overlay content.
const MathTypes = @import("MathTypes.zig");
const CameraRay = @import("CameraRay.zig");
const Vec3 = MathTypes.Vec3;
const Quat = MathTypes.Quat;

/// ScaleWithScreen treats the screen as this many canvas units tall at any resolution, so a HUD laid
/// out once for a 1080 tall screen covers the same share of every screen.
pub const REFERENCE_HEIGHT: f32 = 1080.0;

/// How far in front of the camera every canvas sits, in world units. Any distance draws the same, the
/// canvas scale compensates, and the marcher's hit threshold grows with distance so it stays about a
/// pixel wide for anything past 1. Far is better for float precision: overlay content lives at the
/// camera's world position, and bigger shapes stay resolvable next to a camera far from the origin.
/// It has to stay inside the overlay pass's far distance.
pub const CANVAS_DISTANCE: f32 = 100.0;

/// The overlay pass's own far distance, instead of the game camera's, so a camera that only sees a
/// short way can't clip the canvas. Overlay content pushed further behind the canvas than the canvas
/// is in front of the camera gets cut off.
pub const FAR_DISTANCE: f32 = 2.0 * CANVAS_DISTANCE;

pub const OverlayScaleMode = enum {
    /// A canvas unit is always the same number of pixels (times the OS display scale). A bigger screen
    /// shows more of the canvas. For the editor, tools and debug overlays.
    ConstantPixelSize,
    /// The screen is always REFERENCE_HEIGHT canvas units tall. A bigger screen shows the same canvas
    /// bigger. For game HUDs and menus.
    ScaleWithScreen,
};

/// How many screen pixels one canvas unit covers.
pub fn PixelsPerUnit(mode: OverlayScaleMode, target_height: f32, display_scale: f32) f32 {
    return switch (mode) {
        .ConstantPixelSize => display_scale,
        .ScaleWithScreen => target_height / REFERENCE_HEIGHT,
    };
}

/// Canvas units to world space for one camera: a rotation, one uniform scale and a position. Uniform,
/// so a box on the canvas is still a box in the world, tilted or not.
pub const CanvasTransform = struct {
    Position: Vec3(f32), //the canvas origin (the screen center, canvas z = 0) in world space
    Rotation: Quat(f32),
    Scale: f32, //world units per canvas unit

    pub fn ToWorldPoint(self: CanvasTransform, canvas_point: Vec3(f32)) Vec3(f32) {
        return self.Position.AddVec(canvas_point.MulScalar(self.Scale).QuatRotate(self.Rotation));
    }

    pub fn ToCanvasPoint(self: CanvasTransform, world_point: Vec3(f32)) Vec3(f32) {
        return world_point.SubVec(self.Position).InvQuatRotate(self.Rotation).DivScalar(self.Scale);
    }

    pub fn ToWorldRotation(self: CanvasTransform, canvas_rotation: Quat(f32)) Quat(f32) {
        //parent first, the same order the transform hierarchy composes in
        return self.Rotation.MulQuat(canvas_rotation);
    }

    /// For sizes: half extents, a glyph's offset from its pen, anything that scales but isn't a position.
    pub fn ToWorldVector(self: CanvasTransform, canvas_vector: Vec3(f32)) Vec3(f32) {
        return canvas_vector.MulScalar(self.Scale);
    }

    /// Where a ray crosses the canvas plane (canvas z = 0), in canvas units, or null if the ray runs
    /// along the plane or the plane is behind it. What is under a pixel, for picking and debugging.
    pub fn RayToCanvasPoint(self: CanvasTransform, ray: CameraRay.Ray) ?Vec3(f32) {
        const normal = (Vec3(f32){ .x = 0, .y = 0, .z = 1 }).QuatRotate(self.Rotation);
        const facing = ray.Dir.Dot(normal);
        if (facing == 0) return null;

        const t = self.Position.SubVec(ray.Origin).Dot(normal) / facing;
        if (t < 0) return null;

        return self.ToCanvasPoint(ray.Origin.AddVec(ray.Dir.MulScalar(t)));
    }
};

/// Places the canvas CANVAS_DISTANCE in front of the camera, with one canvas unit sized so it covers
/// `pixels_per_unit` pixels there. The visible height at distance d is 2 * d * tan(fov / 2) world units
/// spread over target_height pixels, which is where the scale comes from. Recomputed every frame from the
/// camera's current fov, so zooming the fov rescales the canvas and overlay content keeps its size.
pub fn ComputeCanvasTransform(camera: CameraRay.Pose, tan_half_fov: f32, target_height: f32, pixels_per_unit: f32) CanvasTransform {
    const forward = Vec3(f32){ .x = 0, .y = 0, .z = -CANVAS_DISTANCE };
    return .{
        .Position = camera.Position.AddVec(forward.QuatRotate(camera.Rotation)),
        .Rotation = camera.Rotation,
        .Scale = 2.0 * CANVAS_DISTANCE * tan_half_fov * pixels_per_unit / target_height,
    };
}
