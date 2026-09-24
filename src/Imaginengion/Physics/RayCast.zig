const std = @import("std");
const MathTypes = @import("../Math/MathTypes.zig");
const Vec3 = MathTypes.Vec3;
const Ray = @import("../Math/CameraRay.zig").Ray;
const HitInfo = @import("../Math/RayIntersect.zig").HitInfo;

const Entity = @import("../ECSObjects/Entity.zig");

/// Which shape was hit, since one entity can carry several (a quad, text, a collider).
pub const RayHitKind = enum {
    Quad,
    Text,
    Collider,
};

/// A ray hitting one of an entity's shapes. No hit is a null ?RayHit, never a half filled one.
pub const RayHit = struct {
    //the entity that owns the shape, which may be a convenience child rather than the game object.
    //walking up to the MainObjectComponent is the caller's decision.
    Entity: Entity,
    T: f32, //distance along the ray
    Position: Vec3(f32),
    Normal: Vec3(f32),
    Kind: RayHitKind,
    StartedInside: bool,

    /// Only for a hit: a miss has T = +inf, which has no position.
    pub fn Init(ray: Ray, hit: HitInfo, entity: Entity, kind: RayHitKind) RayHit {
        std.debug.assert(hit.IsHit());
        return .{
            .Entity = entity,
            .T = hit.T,
            .Position = ray.Origin.AddVec(ray.Dir.MulScalar(hit.T)),
            .Normal = hit.Normal,
            .Kind = kind,
            .StartedInside = hit.StartedInside,
        };
    }
};
