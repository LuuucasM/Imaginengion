//! What game code can ask a world's physics without stepping it: what a ray, or a shape moving along a path, hits
//! first (ShapeCastSystem, which these are the types of). They see the colliders the way the physics step does, where
//! their transforms put them, in every scene, and with no camera. What a view shows (overlay placement, clip regions, a
//! far distance) is the camera's business, and picking things on screen is RayCast.CastRay's.
//! Only the colliders whose boxes the cast reaches are tested: it walks its layer's tree in the world's BVH, the same
//! one the step's broad pass walks.
const std = @import("std");
const Entity = @import("../ECSObjects/Entity.zig");
const LayerType = @import("../ECSComponents/Scene/SceneComponent.zig").LayerType;
const CollisionMask = @import("CollisionMask.zig");
const MathTypes = @import("../Math/MathTypes.zig");
const Vec3 = MathTypes.Vec3;
const Quat = MathTypes.Quat;
pub const Ray = @import("../Math/CameraRay.zig").Ray;

const inf = std.math.inf(f32);

/// Which colliders a query can hit, and how far it looks
pub const QueryOptions = struct {
    /// how far along the ray to look, in world units
    MaxDistance: f32 = inf,
    /// the collision layers it hits: a collider is hit when it is on one of them (its CategoryMask shares a layer with
    /// this). Every layer by default. A collider on no layer collides with nothing in the step, and is not hit here either
    CategoryMask: CollisionMask = .full,
    /// triggers are passed through unless this is set
    HitTriggers: bool = false,
    /// a main object whose colliders are passed through, e.g. the one casting from inside itself
    Ignore: ?Entity = null,
    /// a collider the cast starts inside of (or touching, for a shape) is passed through, the way a shot fired from
    /// inside a box should not stop at its own box
    SkipStartedInside: bool = true,
    /// which layer's colliders it hits, and so which units the ray is in: world units for the game layer, the world's
    /// screen space (canvas units) for the overlay. The two never meet, the same as in the physics step
    Layer: LayerType = .GameLayer,
};

/// The first collider a query hit
pub const PhysicsHit = struct {
    /// the collider that was hit, which may be a convenience child of the main object
    Collider: Entity,
    /// the main object it is part of (Entity.GetMainObject), whose rigid body moves it
    Body: Entity,
    /// how far along the ray the cast got, in world units
    T: f32,
    /// where the cast's centre is when it hits. For a ray that is the hit point on the collider's surface, for a shape
    /// it is where the shape is when it touches (e.g. where to draw the ball at a bounce)
    Position: Vec3(f32),
    /// out of the collider's surface where it was hit, back toward the cast. Minus the ray's direction for a cast that
    /// started inside
    Normal: Vec3(f32),
    StartedInside: bool,
};

/// A shape to sweep along a ray, centred on the ray's origin
pub const CastShape = union(enum) {
    /// the radius
    Sphere: f32,
    Box: struct {
        HalfExtents: Vec3(f32),
        Rotation: Quat(f32) = .{ .w = 1, .x = 0, .y = 0, .z = 0 },
        /// how far its edges and corners are rounded off, see ColliderComponent.mCornerRadius
        CornerRadius: f32 = 0,
    },
};

/// A ray: a sphere of no size, so a ray cast is ShapeCastSystem with this as its shape
pub const RAY: CastShape = .{ .Sphere = 0 };
