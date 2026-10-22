const std = @import("std");
const MathTypes = @import("../Math/MathTypes.zig");
const Vec3 = MathTypes.Vec3;
const Ray = @import("../Math/CameraRay.zig").Ray;
const RayIntersect = @import("../Math/RayIntersect.zig");
const HitInfo = RayIntersect.HitInfo;

const EngineContext = @import("../Core/EngineContext.zig");
const WorldManager = @import("../Core/WorldManager.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const ShapeGeometry = @import("../Renderer/ShapeGeometry.zig");
pub const ViewScenes = ShapeGeometry.ViewScenes;
const CameraView = @import("../Renderer/Renderer.zig").CameraView;
const LayerType = @import("../ECSComponents/Scene/SceneComponent.zig").LayerType;

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const TransformComponent = EntityComponents.TransformComponent;
const ShapeComponent = EntityComponents.ShapeComponent;
const SurfaceComponent = EntityComponents.SurfaceComponent;
const SDFCompiler = @import("../Renderer/SDFCompiler.zig");
const SDFProgram = @import("../Renderer/SDFProgram.zig");
const TextComponent = EntityComponents.TextComponent;
const ColliderComponent = EntityComponents.ColliderComponent;
const TextAsset = @import("../ECSComponents/AComponents.zig").TextAsset;
const LayoutHiddenTag = EntityComponents.LayoutHiddenTag;
const Tracy = @import("../Core/Tracy.zig");
const BVH = @import("../Core/BVH.zig");
const WorldBVH = @import("../Core/WorldBVH.zig");
const CanvasTransform = @import("../Math/OverlayCanvas.zig").CanvasTransform;

/// Which shape was hit, since one entity can carry several (a quad, text, a collider).
pub const RayHitKind = enum {
    Quad,
    Text,
    Collider,
    /// a merge (MergeComponent): the entity is its root, whichever part was clicked
    Merge,
};

/// A ray hitting one of an entity's shapes. No hit is a null ?RayHit, never a half filled one.
pub const RayHit = struct {
    //the entity that owns the shape, which may be a convenience child rather than the main object.
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

/// Which of two hits at exactly the same distance wins: a quad over text over a collider over a merge (RayHitKind's
/// order, so the renderer's quad before glyph rule), then the lower entity id, so the answer never hangs on the order
/// shapes were tested in
fn PickedBefore(a: Picked, b: Picked) bool {
    const a_rank = @intFromEnum(a.Kind);
    const b_rank = @intFromEnum(b.Kind);
    if (a_rank != b_rank) return a_rank < b_rank;
    return a.Entity.mID < b.Entity.mID;
}

/// NearestHit.Consider with ties broken by PickedBefore
fn ConsiderPick(best: *NearestPick, picked: Picked, hit: HitInfo, max_t: f32, skip_started_inside: bool) void {
    if (!hit.IsHit()) return;
    if (hit.StartedInside and skip_started_inside) return;
    if (hit.T > max_t) return;
    if (best.mBest) |current| {
        if (current.Hit.T < hit.T) return;
        if (current.Hit.T == hit.T and !PickedBefore(picked, current.Payload)) return;
    }
    best.mBest = .{ .Payload = picked, .Hit = hit };
}

/// What `ray` hits of what `view_scenes` shows of `world`, seen through `camera_view`: the same shapes the
/// renderer draws for that view, placed the same way (ShapeGeometry), so what gets hit is what was drawn.
/// Overlay shapes are drawn on top of the game layer whatever their depth, so an overlay hit wins over any game
/// hit, and within a layer the nearest hit wins. Hidden shapes and anything past the far distance its layer is
/// drawn to are skipped. Only the shapes whose boxes the ray reaches are tested: it walks the world's trees (WorldBVH),
/// the overlay one in the world's screen space, then the game one if no overlay shape was hit
pub fn CastRay(engine_context: *EngineContext, world: *WorldManager, ray: Ray, camera_view: CameraView, view_scenes: ViewScenes, options: CastOptions) !?RayHit {
    const zone = Tracy.ZoneInit("RayCast::CastRay", @src());
    defer zone.Deinit();

    var masks: ShapeGeometry.ViewMasks = .{};
    var mask_finder = ShapeGeometry.MaskFinder{ .mAllocator = engine_context.FrameAllocator(), .mMasks = &masks };
    const bvh = &world.mBVH;
    const items: u32 = switch (options.Targets) {
        .Visuals => BVH.Mask.PICK,
        .Colliders => BVH.Mask.PHYSICS,
    };

    var overlay = TreeWalk{
        .mEngineContext = engine_context,
        .mWorld = world,
        .mRay = ray,
        .mOptions = options,
        .mMaskFinder = &mask_finder,
        .mTree = bvh.Tree(.OverlayLayer),
        .mScenes = bvh.SceneBits(view_scenes.Overlays),
        .mCanvas = ShapeGeometry.WorldCanvas(world, camera_view),
        .mFar = camera_view.OverlayFarDistance(),
    };
    if (overlay.mScenes != 0) try overlay.Run(items);
    if (overlay.mBest.mBest) |winner| return RayHit.Init(ray, winner.Hit, winner.Payload.Entity, winner.Payload.Kind, .OverlayLayer);

    var game = TreeWalk{
        .mEngineContext = engine_context,
        .mWorld = world,
        .mRay = ray,
        .mOptions = options,
        .mMaskFinder = &mask_finder,
        .mTree = bvh.Tree(.GameLayer),
        .mScenes = switch (view_scenes.Game) {
            .All => std.math.maxInt(u64),
            .One => |scene_id| bvh.SceneBits(&.{scene_id}),
            .None => 0,
        },
        .mCanvas = null,
        .mFar = camera_view.FarDistance,
    };
    if (game.mScenes != 0) try game.Run(items);
    if (game.mBest.mBest) |winner| return RayHit.Init(ray, winner.Hit, winner.Payload.Entity, winner.Payload.Kind, .GameLayer);
    return null;
}

/// One layer's walk for CastRay: down its tree with the ray in the tree's units (the world's screen space for the
/// overlay, world units for the game layer), each item it reaches tested exactly in world space, the way CastRayLinear
/// tests it
const TreeWalk = struct {
    mEngineContext: *EngineContext,
    mWorld: *WorldManager,
    /// in world space, what every item is tested with
    mRay: Ray,
    mOptions: CastOptions,
    mMaskFinder: *ShapeGeometry.MaskFinder,
    mTree: *const WorldBVH.LayerTree,
    /// the scenes the view shows, one bit per SceneSlot
    mScenes: u64,
    /// what places the overlay's screen space in the world, null for the game layer
    mCanvas: ?CanvasTransform,
    /// how far the layer is drawn, in world units
    mFar: f32,
    /// which of the tree's items the cast is after (BVH.Mask): what is clicked, or colliders
    mItems: u32 = 0,
    mBest: NearestPick = .{},

    fn Run(self: *TreeWalk, items: u32) !void {
        self.mItems = items;
        //a canvas only turns, moves and scales evenly, so the ray keeps its shape in canvas units and every distance
        //along it is the world one over the canvas's scale
        var walk_ray = self.mRay;
        if (self.mCanvas) |canvas| {
            walk_ray = .{ .Origin = canvas.ToCanvasPoint(self.mRay.Origin), .Dir = self.mRay.Dir.InvQuatRotate(canvas.Rotation) };
        }
        try BVH.WalkSweep(self.mTree.mNodes.items, walk_ray, 0, self.mFar / self.Scale(), items, self);
    }

    fn Scale(self: TreeWalk) f32 {
        return if (self.mCanvas) |canvas| canvas.Scale else 1.0;
    }

    /// Tests one item, and says how far along the walk's ray is still worth looking: up to the nearest hit so far
    pub fn Visit(self: *TreeWalk, item_ind: u32) !f32 {
        try self.Test(item_ind);
        const reach = if (self.mBest.mBest) |best| best.Hit.T else self.mFar;
        return reach / self.Scale();
    }

    fn Test(self: *TreeWalk, item_ind: u32) !void {
        //a leaf holds items of every kind, the walk only skips whole branches with none of the cast's
        if (self.mTree.mBVHItems.items[item_ind].Mask & self.mItems == 0) return;
        const item = self.mTree.mItems.items[item_ind];
        if (self.mScenes & (@as(u64, 1) << @intCast(item.SceneSlot)) == 0) return;
        const entity = self.mWorld.GetEntity(item.Entity);
        //gone or folded away since the tree was built: neither is drawn, so neither can be clicked
        if (!entity.IsActive() or entity.HasComponent(LayoutHiddenTag)) return;

        const ray = self.mRay;
        const canvas = self.mCanvas;
        switch (item.Kind) {
            .Merge => {
                const frame_allocator = self.mEngineContext.FrameAllocator();
                var programs: SDFCompiler.Programs = .{};
                const compiled = SDFCompiler.Compile(frame_allocator, entity, canvas, &programs) catch |err| switch (err) {
                    error.MergeTooDeep => return,
                    else => return err,
                };
                if (compiled.Parts.Count == 0) return;
                const box = ShapeGeometry.MergeBox(compiled);
                const hit = RayIntersect.RayBox(ray, box.Center, box.Rotation, box.HalfExtents);
                if (!hit.IsHit()) return;
                const point = ray.Origin.AddVec(ray.Dir.MulScalar(hit.T));
                if (SDFProgram.Eval(programs.mInstrs.items, programs.mParts.items, compiled.Range, point, SDFProgram.NoColor{}, {}, {}).D > 0) return;
                try self.Consider(entity, .Merge, hit, true);
            },
            .Quad, .Text => {
                const transform = entity.GetComponent(TransformComponent) orelse return;
                //what isn't drawn can't be clicked
                const surface = entity.GetComponent(SurfaceComponent) orelse return;
                if (!surface.mShouldRender) return;
                if (item.Kind == .Quad) {
                    const quad = ShapeGeometry.QuadOf(entity) orelse return;
                    const box = ShapeGeometry.QuadBox(transform, quad.*, 0, canvas);
                    //rounded, so a click in a cut off corner goes through to whatever is behind
                    try self.Consider(entity, .Quad, RayIntersect.RayRoundedBox2D(ray, box.Center, box.Rotation, box.HalfExtents, box.CornerRadii), true);
                } else {
                    const text = entity.GetComponent(TextComponent) orelse return;
                    const font = try text.mTextAssetHandle.GetAsset(self.mEngineContext, TextAsset);
                    const box = ShapeGeometry.TextBox(TextAsset, transform, text, font, canvas);
                    try self.Consider(entity, .Text, RayIntersect.RayBox(ray, box.Center, box.Rotation, box.HalfExtents), true);
                }
            },
            .Collider => {
                const transform = entity.GetComponent(TransformComponent) orelse return;
                const collider = entity.GetComponent(ColliderComponent) orelse return;
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
                //colliders aren't cut by masks, the same as when they are drawn
                try self.Consider(entity, .Collider, hit, false);
            },
            //drawn, never clicked: the whole text's item is
            .Glyph => {},
        }
    }

    /// Keeps a hit if it is where its masks keep it (when it is cut by any) and wins over the best so far
    fn Consider(self: *TreeWalk, entity: Entity, kind: RayHitKind, hit: HitInfo, comptime masked: bool) !void {
        if (!hit.IsHit()) return;
        if (masked) {
            const mask = try self.mMaskFinder.MaskOf(entity, self.mCanvas);
            if (!InMasks(self.mMaskFinder.mMasks, mask, self.mRay, hit)) return;
        }
        ConsiderPick(&self.mBest, .{ .Entity = entity, .Kind = kind }, hit, self.mFar, self.mOptions.SkipStartedInside);
    }
};

/// CastRay by testing every shape the view shows, with no tree: what CastRay's hits are checked against in the tests.
/// Never called by the engine, so it isn't compiled into it
pub fn CastRayLinear(engine_context: *EngineContext, world: *WorldManager, ray: Ray, camera_view: CameraView, view_scenes: ViewScenes, options: CastOptions) !?RayHit {
    const frame_allocator = engine_context.FrameAllocator();

    var best_overlay: NearestPick = .{};
    var best_game: NearestPick = .{};

    switch (options.Targets) {
        .Visuals => {
            const view = try ShapeGeometry.GatherViewShapes(frame_allocator, world, camera_view, view_scenes, ShapeGeometry.VISUALS_QUERY);

            for (view.Shapes.items) |shape| {
                //overlays come first and any overlay hit wins, so once there is one the game layer can't change the answer
                if (shape.Canvas == null and best_overlay.mBest != null) break;

                const entity = shape.Entity;
                const canvas = shape.Canvas;
                const best = if (canvas != null) &best_overlay else &best_game;
                const far = if (canvas != null) camera_view.OverlayFarDistance() else camera_view.FarDistance;

                //compiled the way the renderer does, its box hit the way the renderer hits it, then its program at the
                //hit says whether it is there
                if (shape.Merge) {
                    var programs: SDFCompiler.Programs = .{};
                    const compiled = SDFCompiler.Compile(frame_allocator, entity, canvas, &programs) catch |err| switch (err) {
                        error.MergeTooDeep => continue,
                        else => return err,
                    };
                    if (compiled.Parts.Count == 0) continue;
                    const box = ShapeGeometry.MergeBox(compiled);
                    const hit = RayIntersect.RayBox(ray, box.Center, box.Rotation, box.HalfExtents);
                    if (!hit.IsHit()) continue;
                    const point = ray.Origin.AddVec(ray.Dir.MulScalar(hit.T));
                    if (SDFProgram.Eval(programs.mInstrs.items, programs.mParts.items, compiled.Range, point, SDFProgram.NoColor{}, {}, {}).D > 0) continue;
                    if (InMasks(&view.Masks, shape.Mask, ray, hit)) ConsiderPick(best, .{ .Entity = entity, .Kind = .Merge }, hit, far, options.SkipStartedInside);
                    continue;
                }

                const transform = entity.GetComponent(TransformComponent) orelse continue;

                //what isn't drawn can't be clicked
                const surface = entity.GetComponent(SurfaceComponent) orelse continue;
                if (!surface.mShouldRender) continue;

                if (entity.GetComponent(ShapeComponent)) |shape_component| {
                    switch (shape_component.mKind) {
                        .Quad => |quad| {
                            const box = ShapeGeometry.QuadBox(transform, quad, 0, canvas);
                            //rounded, so a click in a cut off corner goes through to whatever is behind
                            const hit = RayIntersect.RayRoundedBox2D(ray, box.Center, box.Rotation, box.HalfExtents, box.CornerRadii);
                            if (InMasks(&view.Masks, shape.Mask, ray, hit)) ConsiderPick(best, .{ .Entity = entity, .Kind = .Quad }, hit, far, options.SkipStartedInside);
                        },
                    }
                }
                if (entity.GetComponent(TextComponent)) |text| {
                    const font = try text.mTextAssetHandle.GetAsset(engine_context, TextAsset);
                    const box = ShapeGeometry.TextBox(TextAsset, transform, text, font, canvas);
                    const hit = RayIntersect.RayBox(ray, box.Center, box.Rotation, box.HalfExtents);
                    if (InMasks(&view.Masks, shape.Mask, ray, hit)) ConsiderPick(best, .{ .Entity = entity, .Kind = .Text }, hit, far, options.SkipStartedInside);
                }
            }
        },
        .Colliders => {
            const colliders = try ShapeGeometry.GatherViewShapes(frame_allocator, world, camera_view, view_scenes, .{ .Component = ColliderComponent });

            for (colliders.Shapes.items) |shape| {
                //the same as for visuals: an overlay hit already decides it
                if (shape.Canvas == null and best_overlay.mBest != null) break;

                const entity = shape.Entity;
                const canvas = shape.Canvas;
                const transform = entity.GetComponent(TransformComponent) orelse continue;
                const collider = entity.GetComponent(ColliderComponent).?;
                const best = if (canvas != null) &best_overlay else &best_game;
                const far = if (canvas != null) camera_view.OverlayFarDistance() else camera_view.FarDistance;

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
                ConsiderPick(best, .{ .Entity = entity, .Kind = .Collider }, hit, far, options.SkipStartedInside);
            }
        },
    }

    if (best_overlay.mBest) |winner| return RayHit.Init(ray, winner.Hit, winner.Payload.Entity, winner.Payload.Kind, .OverlayLayer);
    if (best_game.mBest) |winner| return RayHit.Init(ray, winner.Hit, winner.Payload.Entity, winner.Payload.Kind, .GameLayer);
    return null;
}

/// Whether a hit lands where its shape's masks keep it: a part cut off isn't drawn, so it can't be clicked, and
/// whatever is behind it can be
fn InMasks(masks: *const ShapeGeometry.ViewMasks, mask: u32, ray: Ray, hit: HitInfo) bool {
    if (!hit.IsHit()) return true;
    return masks.Contains(mask, ray.Origin.AddVec(ray.Dir.MulScalar(hit.T)));
}
