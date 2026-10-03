//! Covers the physics queries: what a ray, or a shape swept along one, hits first among a world's colliders, with no
//! camera. No window and no GPU.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const PhysicsQueries = @import("../../Physics/PhysicsQueries.zig");

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const ColliderComponent = EntityComponents.ColliderComponent;

const MathTypes = @import("../../Math/MathTypes.zig");
const Vec3 = MathTypes.Vec3;
const Quat = MathTypes.Quat;

const eps: f32 = 0.0001;

const TestWorld = struct {
    mEngineContext: *EngineContext,
    mScene: Scene,

    fn Init() !*TestWorld {
        const self = try std.heap.page_allocator.create(TestWorld);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext), .mScene = undefined };
        self.mEngineContext.* = .{};
        try self.mEngineContext.mEditorWorld.Init(self.mEngineContext.EngineAllocator());
        self.mScene = try self.mEngineContext.mEditorWorld.NewScene(self.mEngineContext, .GameLayer, Scene.DefaultConfig);
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        engine_context.mEditorWorld.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    /// A collider of the given shape in category 0, at `position`. A unit box, or a sphere of radius 0.5
    fn Collider(self: *TestWorld, shape: ColliderComponent.Shapes, position: Vec3(f32)) !Entity {
        const entity = try self.mScene.CreateEntity(self.mEngineContext, Entity.DefaultConfig);
        var collider: ColliderComponent = .{ .mShape = shape };
        collider.mCollisionFilter.CategoryMask.set(0);
        collider.mCollisionFilter.RespondMask.set(0);
        _ = try entity.AddComponent(self.mEngineContext, collider);
        try entity.SetTranslation(self.mEngineContext, position);
        return entity;
    }

    fn RayCast(self: *TestWorld, ray: PhysicsQueries.Ray, options: PhysicsQueries.QueryOptions) !?PhysicsQueries.PhysicsHit {
        return PhysicsQueries.RayCast(self.mEngineContext, &self.mEngineContext.mEditorWorld, ray, options);
    }

    fn ShapeCast(self: *TestWorld, shape: PhysicsQueries.CastShape, ray: PhysicsQueries.Ray, options: PhysicsQueries.QueryOptions) !?PhysicsQueries.PhysicsHit {
        return PhysicsQueries.ShapeCast(self.mEngineContext, &self.mEngineContext.mEditorWorld, shape, ray, options);
    }
};

/// From x = -5 along +x
const ALONG_X: PhysicsQueries.Ray = .{ .Origin = .{ .x = -5, .y = 0, .z = 0 }, .Dir = .{ .x = 1, .y = 0, .z = 0 } };

test "a ray hits the nearest collider, with no camera" {
    const world = try TestWorld.Init();
    defer world.Deinit();

    const far = try world.Collider(.Box, .{ .x = 3, .y = 0, .z = 0 });
    const near = try world.Collider(.Box, .{ .x = 0, .y = 0, .z = 0 });
    _ = far;

    const hit = (try world.RayCast(ALONG_X, .{})).?;
    try std.testing.expectEqual(near.mID, hit.Collider.mID);
    try std.testing.expectEqual(near.mID, hit.Body.mID);
    try std.testing.expectApproxEqAbs(@as(f32, 4.5), hit.T, eps);
    try std.testing.expectApproxEqAbs(@as(f32, -0.5), hit.Position.x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, -1), hit.Normal.x, eps);
}

test "a ray only looks as far as its max distance" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    _ = try world.Collider(.Sphere, .{ .x = 0, .y = 0, .z = 0 });

    try std.testing.expect(try world.RayCast(ALONG_X, .{ .MaxDistance = 4 }) == null);
    try std.testing.expect(try world.RayCast(ALONG_X, .{ .MaxDistance = 5 }) != null);
}

test "a ray passes through triggers, other categories and the game object it ignores" {
    const world = try TestWorld.Init();
    defer world.Deinit();

    const trigger = try world.Collider(.Box, .{ .x = -2, .y = 0, .z = 0 });
    trigger.GetComponent(ColliderComponent).?.mCollisionFilter.IsTrigger = true;
    const other_category = try world.Collider(.Box, .{ .x = 0, .y = 0, .z = 0 });
    other_category.GetComponent(ColliderComponent).?.mCollisionFilter.CategoryMask = .empty;
    other_category.GetComponent(ColliderComponent).?.mCollisionFilter.CategoryMask.set(3);
    const ignored = try world.Collider(.Box, .{ .x = 2, .y = 0, .z = 0 });
    const last = try world.Collider(.Box, .{ .x = 4, .y = 0, .z = 0 });

    //category 0 only, so the category 3 box is passed through too
    var only_zero: std.StaticBitSet(32) = .empty;
    only_zero.set(0);
    const hit = (try world.RayCast(ALONG_X, .{ .CategoryMask = only_zero, .Ignore = ignored })).?;
    try std.testing.expectEqual(last.mID, hit.Collider.mID);

    //and each is hit once it is asked for
    try std.testing.expectEqual(trigger.mID, (try world.RayCast(ALONG_X, .{ .HitTriggers = true })).?.Collider.mID);
    try std.testing.expectEqual(other_category.mID, (try world.RayCast(ALONG_X, .{})).?.Collider.mID);
}

test "a ray that starts inside a collider passes through it unless asked" {
    const world = try TestWorld.Init();
    defer world.Deinit();

    const around = try world.Collider(.Box, .{ .x = -5, .y = 0, .z = 0 });
    const ahead = try world.Collider(.Box, .{ .x = 0, .y = 0, .z = 0 });

    try std.testing.expectEqual(ahead.mID, (try world.RayCast(ALONG_X, .{})).?.Collider.mID);

    const inside = (try world.RayCast(ALONG_X, .{ .SkipStartedInside = false })).?;
    try std.testing.expectEqual(around.mID, inside.Collider.mID);
    try std.testing.expect(inside.StartedInside);
    try std.testing.expectEqual(@as(f32, 0), inside.T);
}

test "a ray sees a box's corner radius" {
    const world = try TestWorld.Init();
    defer world.Deinit();

    //a unit box rounded by 0.3: a ray along its edge 0.45 up clips the sharp box but passes the rounded corner
    const box = try world.Collider(.Box, .{ .x = 0, .y = 0, .z = 0 });
    const edge_ray: PhysicsQueries.Ray = .{ .Origin = .{ .x = -5, .y = 0.45, .z = 0.45 }, .Dir = .{ .x = 1, .y = 0, .z = 0 } };
    try std.testing.expect(try world.RayCast(edge_ray, .{}) != null);

    box.GetComponent(ColliderComponent).?.mCornerRadius = 0.3;
    try std.testing.expect(try world.RayCast(edge_ray, .{}) == null);
}

test "a ray sees where something was just moved to" {
    const world = try TestWorld.Init();
    defer world.Deinit();

    const box = try world.Collider(.Box, .{ .x = 0, .y = 0, .z = 0 });
    _ = (try world.RayCast(ALONG_X, .{})).?;

    //moved out of the way, with no physics step in between to work out its world transform
    try box.SetTranslation(world.mEngineContext, .{ .x = 0, .y = 10, .z = 0 });
    try std.testing.expect(try world.RayCast(ALONG_X, .{}) == null);
}

test "a sphere cast stops a radius short of what it hits, and says where the sphere is" {
    const world = try TestWorld.Init();
    defer world.Deinit();

    //against a unit box's face at -0.5 a radius 0.25 sphere stops with its centre at -0.75
    _ = try world.Collider(.Box, .{ .x = 0, .y = 0, .z = 0 });
    const hit = (try world.ShapeCast(.{ .Sphere = 0.25 }, ALONG_X, .{})).?;
    try std.testing.expectApproxEqAbs(@as(f32, 4.25), hit.T, eps);
    try std.testing.expectApproxEqAbs(@as(f32, -0.75), hit.Position.x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, -1), hit.Normal.x, eps);

    //and a sphere passing 0.7 above it still clips the box, which a ray would miss
    const above: PhysicsQueries.Ray = .{ .Origin = .{ .x = -5, .y = 0.7, .z = 0 }, .Dir = .{ .x = 1, .y = 0, .z = 0 } };
    try std.testing.expect(try world.RayCast(above, .{}) == null);
    try std.testing.expect(try world.ShapeCast(.{ .Sphere = 0.25 }, above, .{}) != null);
}

test "a sphere cast against a sphere stops at both radii" {
    const world = try TestWorld.Init();
    defer world.Deinit();

    _ = try world.Collider(.Sphere, .{ .x = 0, .y = 0, .z = 0 });
    const hit = (try world.ShapeCast(.{ .Sphere = 0.25 }, ALONG_X, .{})).?;
    try std.testing.expectApproxEqAbs(@as(f32, -0.75), hit.Position.x, eps);
}

test "a box cast against a turned box stops at its corner" {
    const world = try TestWorld.Init();
    defer world.Deinit();

    //a unit box turned 45 degrees reaches sqrt(2) / 2 toward the cast, and the cast unit box reaches 0.5 ahead of
    //its centre, so its centre stops 0.5 + 0.7071 short of the turned box's
    const turned = try world.Collider(.Box, .{ .x = 0, .y = 0, .z = 0 });
    try turned.SetRotation(world.mEngineContext, Quat(f32).FromAxisAngle(.{ .x = 0, .y = 0, .z = 1 }, std.math.pi / 4.0));

    const hit = (try world.ShapeCast(.{ .Box = .{ .HalfExtents = .{ .x = 0.5, .y = 0.5, .z = 0.5 } } }, ALONG_X, .{})).?;
    try std.testing.expectApproxEqAbs(@as(f32, -0.5 - std.math.sqrt1_2), hit.Position.x, 0.002);
    try std.testing.expectApproxEqAbs(@as(f32, -1), hit.Normal.x, 0.01);
    try std.testing.expect(!hit.StartedInside);
}
