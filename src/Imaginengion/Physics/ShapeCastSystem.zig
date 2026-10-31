//! The first collider a shape hits moving from a ray's origin along its direction (which must be of length 1), as a
//! system. A ray cast is the same with PhysicsQueries.RAY, a sphere of no size:
//!
//!     const hit = try engine_context.mSystems.RunSystem(ShapeCastSystem, engine_context, .{ world, PhysicsQueries.RAY, ray, options });
//!
//! The world's transforms are brought up to date first, so a cast straight after moving something sees it moved, and
//! when anything had moved the tree's colliders are placed again too: both are runs of their own inside this one. Each
//! pairing has the simplest test that is exact for it: a sphere against a sphere is a ray against a sphere of both radii,
//! a sphere against a box a ray against the box grown by the radius, which is a rounded box. A box has no such shortcut and is swept by sphere tracing instead (Collisions.SweepAlong), which a path
//! grazing a surface can run out of steps on and miss
const std = @import("std");
const BVHRefitSystem = @import("../Core/BVHRefitSystem.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const WorldManager = @import("../Core/WorldManager.zig");
const WorldBVH = @import("../Core/WorldBVH.zig");
const BVH = @import("../Core/BVH.zig");
const Entity = @import("../ECSObjects/Entity.zig");

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const ColliderComponent = EntityComponents.ColliderComponent;
const TransformComponent = EntityComponents.TransformComponent;
const TransformDirtyTag = EntityComponents.TransformDirtyTag;
const OverlayLayerTag = EntityComponents.OverlayLayerTag;
const GameLayerTag = EntityComponents.GameLayerTag;

const Collisions = @import("Collisions.zig");
const TransformSystem = @import("TransformSystem.zig");
const PhysicsQueries = @import("PhysicsQueries.zig");
const QueryOptions = PhysicsQueries.QueryOptions;
const PhysicsHit = PhysicsQueries.PhysicsHit;
const CastShape = PhysicsQueries.CastShape;
const Ray = PhysicsQueries.Ray;

const RayIntersect = @import("../Math/RayIntersect.zig");
const HitInfo = RayIntersect.HitInfo;

pub const Name = "ShapeCast";

pub fn Run(engine_context: *EngineContext, world: *WorldManager, shape: CastShape, ray: Ray, options: QueryOptions) !?PhysicsHit {
    //anything moved since the tree was last refit, whatever moved it: a script teleporting a body, the last substep
    if (world.NumEntitiesWith(TransformDirtyTag) > 0) {
        try engine_context.mSystems.RunSystem(TransformSystem, engine_context, .{world});
        try engine_context.mSystems.RunSystem(BVHRefitSystem, engine_context, .{ world, BVH.Mask.PHYSICS });
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

/// The cast by testing every collider of the layer, with no tree: what the cast's hits are checked against in the
/// tests. Never run by the engine, so it isn't compiled into it
pub const Linear = struct {
    pub const Name = "ShapeCastLinear";

    pub fn Run(engine_context: *EngineContext, world: *WorldManager, shape: CastShape, ray: Ray, options: QueryOptions) !?PhysicsHit {
        try engine_context.mSystems.RunSystem(TransformSystem, engine_context, .{world});
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
};

/// Which colliders a query's options let it hit
const Filter = struct {
    mOptions: QueryOptions,
    mIgnoreBody: ?Entity.Type,

    fn Init(options: QueryOptions) Filter {
        return .{ .mOptions = options, .mIgnoreBody = if (options.Ignore) |ignore| ignore.GetMainObject().mID else null };
    }

    const Target = struct { Transform: *const TransformComponent, Collider: *const ColliderComponent };

    /// `entity`'s collider and transform if the query can hit it: in its layer, a trigger only when asked for, on one
    /// of its layers, and not part of the body it ignores
    fn Hittable(self: Filter, entity: Entity) ?Target {
        //the tree can still name an entity destroyed since it was built
        if (!entity.IsActive()) return null;
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
fn CastAgainst(shape: CastShape, ray: Ray, max_distance: f32, transform: *const TransformComponent, collider: *const ColliderComponent) HitInfo {
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
fn SweepBox(box: @FieldType(CastShape, "Box"), ray: Ray, max_distance: f32, transform: *const TransformComponent, collider: *const ColliderComponent) HitInfo {
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
