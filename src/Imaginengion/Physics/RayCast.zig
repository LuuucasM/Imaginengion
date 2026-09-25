const std = @import("std");
const MathTypes = @import("../Math/MathTypes.zig");
const Vec3 = MathTypes.Vec3;
const Ray = @import("../Math/CameraRay.zig").Ray;
const RayIntersect = @import("../Math/RayIntersect.zig");
const HitInfo = RayIntersect.HitInfo;
const OverlayCanvas = @import("../Math/OverlayCanvas.zig");

const EngineContext = @import("../Core/EngineContext.zig");
const WorldManager = @import("../Core/WorldManager.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const GroupQuery = @import("../ECS/ECSManager.zig").GroupQuery;
const ShapeGeometry = @import("../Renderer/ShapeGeometry.zig");
const CameraView = @import("../Renderer/Renderer.zig").CameraView;
const LayerType = @import("../ECSComponents/Scene/SceneComponent.zig").LayerType;

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const TransformComponent = EntityComponents.TransformComponent;
const QuadComponent = EntityComponents.QuadComponent;
const TextComponent = EntityComponents.TextComponent;
const ColliderComponent = EntityComponents.ColliderComponent;
const TextAsset = @import("../ECSComponents/AComponents.zig").TextAsset;

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
    Layer: LayerType, //overlay hits are the UI, drawn on top of the game layer
    StartedInside: bool,

    /// Only for a hit: a miss has T = +inf, which has no position.
    pub fn Init(ray: Ray, hit: HitInfo, entity: Entity, kind: RayHitKind, layer: LayerType) RayHit {
        std.debug.assert(hit.IsHit());
        return .{
            .Entity = entity,
            .T = hit.T,
            .Position = ray.Origin.AddVec(ray.Dir.MulScalar(hit.T)),
            .Normal = hit.Normal,
            .Kind = kind,
            .Layer = layer,
            .StartedInside = hit.StartedInside,
        };
    }
};

pub const CastOptions = struct {
    /// What's drawn (quads and text) for clicking on things, or the physics shapes (colliders) for
    /// questions like what a bullet hits. Colliders can be invisible, or not match what's drawn.
    Targets: enum { Visuals, Colliders } = .Visuals,
    /// A ray that starts inside a shape "hits" it at distance 0. Usually unwanted: a camera inside a
    /// big box would hit that box every time.
    SkipStartedInside: bool = true,
};

/// The nearest hit so far within one layer.
const BestHit = struct {
    Entity: Entity,
    Hit: HitInfo,
    Kind: RayHitKind,
};

/// What `ray` hits in `world`, seen through `camera_view`: every shape is placed the way the renderer
/// placed it for that camera (ShapeGeometry), so what gets hit is what was drawn. Overlay shapes are
/// drawn on top of the game layer whatever their depth, so an overlay hit wins over any game hit, and
/// within a layer the nearest hit wins. Hidden shapes and anything past the far distance its layer is
/// drawn to are skipped.
pub fn CastRay(engine_context: *EngineContext, world: *WorldManager, ray: Ray, camera_view: CameraView, options: CastOptions) !?RayHit {
    const frame_allocator = engine_context.FrameAllocator();

    var best_overlay: ?BestHit = null;
    var best_game: ?BestHit = null;

    switch (options.Targets) {
        .Visuals => {
            const shape_ids = try world.GetEntityGroup(frame_allocator, GroupQuery{
                .Or = &[_]GroupQuery{
                    GroupQuery{ .Component = QuadComponent },
                    GroupQuery{ .Component = TextComponent },
                },
            });

            for (shape_ids.items) |shape_id| {
                const entity = world.GetEntity(shape_id);
                const transform = entity.GetComponent(TransformComponent) orelse continue;
                const canvas = ShapeGeometry.EntityCanvas(entity, camera_view);
                const best = if (canvas != null) &best_overlay else &best_game;
                const far = if (canvas != null) OverlayCanvas.FAR_DISTANCE else camera_view.FarDistance;

                if (entity.GetComponent(QuadComponent)) |quad| {
                    if (quad.mShouldRender) {
                        const box = ShapeGeometry.QuadBox(transform, quad, canvas);
                        Consider(best, entity, .Quad, RayIntersect.RayBox(ray, box.Center, box.Rotation, box.HalfExtents), far, options);
                    }
                }
                if (entity.GetComponent(TextComponent)) |text| {
                    if (text.mShouldRender) {
                        const font = try text.mTextAssetHandle.GetAsset(engine_context, TextAsset);
                        const box = ShapeGeometry.TextBox(TextAsset, transform, text, font, canvas);
                        Consider(best, entity, .Text, RayIntersect.RayBox(ray, box.Center, box.Rotation, box.HalfExtents), far, options);
                    }
                }
            }
        },
        .Colliders => {
            const collider_ids = try world.GetEntityGroup(frame_allocator, .{ .Component = ColliderComponent });

            for (collider_ids.items) |collider_id| {
                const entity = world.GetEntity(collider_id);
                const transform = entity.GetComponent(TransformComponent) orelse continue;
                const collider = entity.GetComponent(ColliderComponent).?;
                const canvas = ShapeGeometry.EntityCanvas(entity, camera_view);
                const best = if (canvas != null) &best_overlay else &best_game;
                const far = if (canvas != null) OverlayCanvas.FAR_DISTANCE else camera_view.FarDistance;

                const hit = switch (collider.mShape) {
                    .Box => blk: {
                        const box = ShapeGeometry.ColliderBox(transform, collider, canvas);
                        break :blk RayIntersect.RayBox(ray, box.Center, box.Rotation, box.HalfExtents);
                    },
                    .Sphere => blk: {
                        const sphere = ShapeGeometry.ColliderSphere(transform, collider, canvas);
                        break :blk RayIntersect.RaySphere(ray, sphere.Center, sphere.Radius);
                    },
                };
                Consider(best, entity, .Collider, hit, far, options);
            }
        },
    }

    if (best_overlay) |winner| return RayHit.Init(ray, winner.Hit, winner.Entity, winner.Kind, .OverlayLayer);
    if (best_game) |winner| return RayHit.Init(ray, winner.Hit, winner.Entity, winner.Kind, .GameLayer);
    return null;
}

/// Keeps `hit` if it counts and is nearer than the layer's best so far.
fn Consider(best: *?BestHit, entity: Entity, kind: RayHitKind, hit: HitInfo, far: f32, options: CastOptions) void {
    if (!hit.IsHit()) return;
    if (hit.StartedInside and options.SkipStartedInside) return;
    //not drawn past its layer's far distance, so not something that can be hit either
    if (hit.T > far) return;
    if (best.*) |current| {
        if (current.Hit.T <= hit.T) return;
    }
    best.* = .{ .Entity = entity, .Hit = hit, .Kind = kind };
}
