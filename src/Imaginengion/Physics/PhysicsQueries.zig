//! What game code can ask a world's physics without stepping it: what a ray, or a shape moving along a path, hits
//! first. They see the colliders the way the physics step does, where their transforms put them, in every scene, and
//! with no camera. What a view shows (overlay placement, clip regions, a far distance) is the camera's business, and
//! picking things on screen is RayCast.CastRay's.
//! Only the colliders whose boxes the cast reaches are tested: it walks its layer's tree in the world's BVH, the same
//! one the step's broad pass walks.
const std = @import("std");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const WorldManager = @import("../Core/WorldManager.zig");
const WorldBVH = @import("../Core/WorldBVH.zig");
const BVH = @import("../Core/BVH.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const LayerType = @import("../ECSComponents/Scene/SceneComponent.zig").LayerType;

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const ColliderComponent = EntityComponents.ColliderComponent;
const TransformComponent = EntityComponents.TransformComponent;
const TransformDirtyTag = EntityComponents.TransformDirtyTag;
const OverlayLayerTag = EntityComponents.OverlayLayerTag;
const GameLayerTag = EntityComponents.GameLayerTag;

const Collisions = @import("Collisions.zig");
const CollisionMask = @import("CollisionMask.zig");
const UpdateWorldTransforms = @import("PhysicsManager.zig").UpdateWorldTransforms;

const RayIntersect = @import("../Math/RayIntersect.zig");
const HitInfo = RayIntersect.HitInfo;
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

/// The first collider `ray` hits, see ShapeCast. A ray is a sphere of no size, so it is that
pub fn RayCast(engine_context: *EngineContext, world: *WorldManager, ray: Ray, options: QueryOptions) !?PhysicsHit {
    return ShapeCast(engine_context, world, .{ .Sphere = 0 }, ray, options);
}

/// The first collider `shape` hits moving from the ray's origin along its direction (which must be of length 1).
/// The world's transforms are brought up to date first, so a cast straight after moving something sees it moved, and
/// when anything had moved the tree's colliders are placed again too. Each pairing has the simplest test that is exact
/// for it: a sphere against a sphere is a ray against a sphere of both radii, a sphere against a box a ray against the
/// box grown by the radius, which is a rounded box. A box has no such shortcut and is swept by sphere tracing instead
/// (Collisions.SweepAlong), which a path grazing a surface can run out of steps on and miss
pub fn ShapeCast(engine_context: *EngineContext, world: *WorldManager, shape: CastShape, ray: Ray, options: QueryOptions) !?PhysicsHit {
    const zone = Tracy.ZoneInit("PhysicsQueries::ShapeCast", @src());
    defer zone.Deinit();

    //anything moved since the tree was last refit, whatever moved it: a script teleporting a body, the last substep
    if (world.NumEntitiesWith(TransformDirtyTag) > 0) {
        try UpdateWorldTransforms(world, engine_context);
        world.mBVH.Refit(engine_context, world, BVH.Mask.PHYSICS);
    }

    const Visitor = struct {
        mWorld: *WorldManager,
        mTree: *const WorldBVH.LayerTree,
        mFilter: Filter,
        mShape: CastShape,
        mRay: Ray,
        mOptions: QueryOptions,
        mNearest: RayIntersect.NearestHit(Entity) = .{},

        /// how far along the ray is still worth looking: up to the nearest hit so far
        pub fn Visit(self: *@This(), item_ind: u32) f32 {
            const item = self.mTree.mBVHItems.items[item_ind];
            if (item.Mask & BVH.Mask.PHYSICS != 0) {
                const entity = self.mWorld.GetEntity(self.mTree.mItems.items[item_ind].Entity);
                if (self.mFilter.Hittable(entity)) |hittable| {
                    const hit = CastAgainst(self.mShape, self.mRay, self.mOptions.MaxDistance, hittable.Transform, hittable.Collider);
                    self.mNearest.Consider(entity, hit, self.mOptions.MaxDistance, self.mOptions.SkipStartedInside);
                }
            }
            return if (self.mNearest.mBest) |best| best.Hit.T else self.mOptions.MaxDistance;
        }
    };
    //how far the cast reaches out from the ray every way, whichever way a box is turned. A box's rounding cuts into its
    //half extents rather than growing past them
    const radius: f32 = switch (shape) {
        .Sphere => |sphere_radius| sphere_radius,
        .Box => |box| box.HalfExtents.Len(),
    };
    const tree = world.mBVH.Tree(options.Layer);
    var visitor = Visitor{ .mWorld = world, .mTree = tree, .mFilter = .Init(options), .mShape = shape, .mRay = ray, .mOptions = options };
    try BVH.WalkSweep(tree.mNodes.items, ray, radius, options.MaxDistance, BVH.Mask.PHYSICS, &visitor);
    return HitFrom(ray, visitor.mNearest);
}

/// ShapeCast by testing every collider of the layer, with no tree: what ShapeCast's hits are checked against in the
/// tests. Never called by the engine, so it isn't compiled into it
pub fn ShapeCastLinear(engine_context: *EngineContext, world: *WorldManager, shape: CastShape, ray: Ray, options: QueryOptions) !?PhysicsHit {
    try UpdateWorldTransforms(world, engine_context);
    const filter = Filter.Init(options);
    const colliders = try world.GetEntityGroup(engine_context.FrameAllocator(), .{ .Component = ColliderComponent });
    var nearest: RayIntersect.NearestHit(Entity) = .{};
    for (colliders.items) |collider_id| {
        const entity = world.GetEntity(collider_id);
        const hittable = filter.Hittable(entity) orelse continue;
        nearest.Consider(entity, CastAgainst(shape, ray, options.MaxDistance, hittable.Transform, hittable.Collider), options.MaxDistance, options.SkipStartedInside);
    }
    return HitFrom(ray, nearest);
}

/// Which colliders a query's options let it hit
const Filter = struct {
    mOptions: QueryOptions,
    mIgnoreBody: ?Entity.Type,

    fn Init(options: QueryOptions) Filter {
        return .{ .mOptions = options, .mIgnoreBody = if (options.Ignore) |ignore| ignore.GetMainObject().mID else null };
    }

    const Target = struct { Transform: *TransformComponent, Collider: *ColliderComponent };

    /// `entity`'s collider and transform if the query can hit it: in its layer, a trigger only when asked for, on one
    /// of its layers, and not part of the body it ignores
    fn Hittable(self: Filter, entity: Entity) ?Target {
        const collider = entity.GetComponent(ColliderComponent) orelse return null;
        const transform = entity.GetComponent(TransformComponent) orelse return null;
        const in_layer = switch (self.mOptions.Layer) {
            .GameLayer => entity.HasComponent(GameLayerTag),
            .OverlayLayer => entity.HasComponent(OverlayLayerTag),
        };
        if (!in_layer) return null;
        if (collider.mCollisionFilter.IsTrigger and !self.mOptions.HitTriggers) return null;
        if (!collider.mCollisionFilter.CategoryMask.intersects(self.mOptions.CategoryMask)) return null;
        if (self.mIgnoreBody) |ignore_id| {
            if (entity.GetMainObject().mID == ignore_id) return null;
        }
        return .{ .Transform = transform, .Collider = collider };
    }
};

/// The hit a query reports from the nearest one it found
fn HitFrom(ray: Ray, nearest: RayIntersect.NearestHit(Entity)) ?PhysicsHit {
    const winner = nearest.mBest orelse return null;
    const hit_point = ray.Origin.AddVec(ray.Dir.MulScalar(winner.Hit.T));
    return .{
        .Collider = winner.Payload,
        .Body = winner.Payload.GetMainObject(),
        .T = winner.Hit.T,
        .Position = hit_point,
        .Normal = winner.Hit.Normal,
        .StartedInside = winner.Hit.StartedInside,
    };
}

/// `shape` swept along `ray` against one collider. The switch is exhaustive the same way TestShapes' is
fn CastAgainst(shape: CastShape, ray: Ray, max_distance: f32, transform: *TransformComponent, collider: *ColliderComponent) HitInfo {
    const scale = transform.GetWorldScale();
    return switch (shape) {
        .Sphere => |radius| switch (collider.mShape) {
            .Sphere => RayIntersect.RaySphere(ray, transform.GetWorldPosition(), collider.GetWorldRadius(scale) + radius),
            //the box grown by the radius all round, which rounds it by the radius on top of its own rounding
            .Box => RayIntersect.RayRoundedBox(
                ray,
                transform.GetWorldPosition(),
                transform.GetWorldRotation(),
                collider.GetWorldHalfExtents(scale).AddVec(.FromScalar(radius)),
                collider.GetWorldCornerRadius(scale) + radius,
            ),
        },
        .Box => |box| SweepBox(box, ray, max_distance, transform, collider),
    };
}

/// A box swept along `ray` against one collider by sphere tracing, see Collisions.SweepAlong
fn SweepBox(box: @FieldType(CastShape, "Box"), ray: Ray, max_distance: f32, transform: *TransformComponent, collider: *ColliderComponent) HitInfo {
    var cast_transform: TransformComponent = .{};
    cast_transform.SetWorldPosition(ray.Origin);
    cast_transform.SetWorldRotation(box.Rotation);
    cast_transform.SetWorldScale(.{ .x = 1, .y = 1, .z = 1 });
    var cast_collider: ColliderComponent = .{
        .mShape = .Box,
        .mBoxSize = box.HalfExtents.MulScalar(2),
        .mCornerRadius = box.CornerRadius,
    };

    //the collider is the origin and the box the target that moves, so the normal comes out of the collider toward it
    var contact: Collisions.Contact = .{ .mNormal = .{ .x = 0, .y = 0, .z = 0 }, .mSeparation = 0 };
    const travelled = Collisions.SweepAlong(&contact, transform, collider, &cast_transform, &cast_collider, ray.Dir, max_distance) orelse return .miss;

    //touching at the start is a hit at 0 from outside, overlapping is starting inside
    if (travelled == 0 and Collisions.TestShapes(&contact, transform, collider, &cast_transform, &cast_collider)) {
        return .{ .T = 0, .TExit = 0, .Normal = ray.Dir.Neg(), .StartedInside = true };
    }
    //where the box would come out again is not worked out, a sweep only finds the way in
    return .{ .T = travelled, .TExit = travelled, .Normal = contact.mNormal, .StartedInside = false };
}
