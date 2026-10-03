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
const ShapeGeometry = @import("../Renderer/ShapeGeometry.zig");
pub const ViewScenes = ShapeGeometry.ViewScenes;
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
    /// What's drawn (quads and text) for clicking on things, or the colliders as this view shows them, e.g.
    /// clicking on an invisible collider in the editor. Colliders can be invisible, or not match what's drawn.
    /// Game logic asking what a bullet hits wants PhysicsQueries instead, which needs no camera
    Targets: enum { Visuals, Colliders } = .Visuals,
    /// A ray that starts inside a shape "hits" it at distance 0. Usually unwanted: a camera inside a
    /// big box would hit that box every time.
    SkipStartedInside: bool = true,
};

/// What a hit was on: the nearest of these within one layer wins
const Picked = struct {
    Entity: Entity,
    Kind: RayHitKind,
};
const NearestPick = RayIntersect.NearestHit(Picked);

/// What `ray` hits of what `view_scenes` shows of `world`, seen through `camera_view`: the same shapes the
/// renderer draws for that view, placed the same way (ShapeGeometry), so what gets hit is what was drawn.
/// Overlay shapes are drawn on top of the game layer whatever their depth, so an overlay hit wins over any game
/// hit, and within a layer the nearest hit wins. Hidden shapes and anything past the far distance its layer is
/// drawn to are skipped.
pub fn CastRay(engine_context: *EngineContext, world: *WorldManager, ray: Ray, camera_view: CameraView, view_scenes: ViewScenes, options: CastOptions) !?RayHit {
    const frame_allocator = engine_context.FrameAllocator();

    var best_overlay: NearestPick = .{};
    var best_game: NearestPick = .{};

    switch (options.Targets) {
        .Visuals => {
            const shapes = try ShapeGeometry.GatherViewShapes(frame_allocator, world, camera_view, view_scenes, ShapeGeometry.VISUALS_QUERY);

            for (shapes.items) |shape| {
                //overlays come first and any overlay hit wins, so once there is one the game layer can't change the answer
                if (shape.Canvas == null and best_overlay.mBest != null) break;

                const entity = shape.Entity;
                const canvas = shape.Canvas;
                const transform = entity.GetComponent(TransformComponent) orelse continue;
                const best = if (canvas != null) &best_overlay else &best_game;
                const far = if (canvas != null) OverlayCanvas.FAR_DISTANCE else camera_view.FarDistance;

                if (entity.GetComponent(QuadComponent)) |quad| {
                    if (quad.mShouldRender) {
                        const box = ShapeGeometry.QuadBox(transform, quad, canvas);
                        //rounded, so a click in a cut off corner goes through to whatever is behind
                        const hit = RayIntersect.RayRoundedBox2D(ray, box.Center, box.Rotation, box.HalfExtents, box.CornerRadii);
                        if (InClip(shape.Clip, ray, hit)) best.Consider(.{ .Entity = entity, .Kind = .Quad }, hit, far, options.SkipStartedInside);
                    }
                }
                if (entity.GetComponent(TextComponent)) |text| {
                    if (text.mShouldRender) {
                        const font = try text.mTextAssetHandle.GetAsset(engine_context, TextAsset);
                        const box = ShapeGeometry.TextBox(TextAsset, transform, text, font, canvas);
                        const hit = RayIntersect.RayBox(ray, box.Center, box.Rotation, box.HalfExtents);
                        if (InClip(shape.Clip, ray, hit)) best.Consider(.{ .Entity = entity, .Kind = .Text }, hit, far, options.SkipStartedInside);
                    }
                }
            }
        },
        .Colliders => {
            const colliders = try ShapeGeometry.GatherViewShapes(frame_allocator, world, camera_view, view_scenes, .{ .Component = ColliderComponent });

            for (colliders.items) |shape| {
                //the same as for visuals: an overlay hit already decides it
                if (shape.Canvas == null and best_overlay.mBest != null) break;

                const entity = shape.Entity;
                const canvas = shape.Canvas;
                const transform = entity.GetComponent(TransformComponent) orelse continue;
                const collider = entity.GetComponent(ColliderComponent).?;
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
                best.Consider(.{ .Entity = entity, .Kind = .Collider }, hit, far, options.SkipStartedInside);
            }
        },
    }

    if (best_overlay.mBest) |winner| return RayHit.Init(ray, winner.Hit, winner.Payload.Entity, winner.Payload.Kind, .OverlayLayer);
    if (best_game.mBest) |winner| return RayHit.Init(ray, winner.Hit, winner.Payload.Entity, winner.Payload.Kind, .GameLayer);
    return null;
}

/// Whether a hit lands inside the clip region its shape is cut to: a part cut off isn't drawn, so it can't be clicked,
/// and whatever is behind it can be
fn InClip(clip: ?ShapeGeometry.ViewClip, ray: Ray, hit: HitInfo) bool {
    const view_clip = clip orelse return true;
    if (!hit.IsHit()) return true;
    return ShapeGeometry.ClipContains(view_clip.Rect, ray.Origin.AddVec(ray.Dir.MulScalar(hit.T)));
}
