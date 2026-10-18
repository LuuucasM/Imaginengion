//! Covers the physics queries: what a ray, or a shape swept along one, hits first among a world's colliders, with no
//! camera. No window and no GPU.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const PhysicsQueries = @import("../../Physics/PhysicsQueries.zig");
const CollisionMask = @import("../../Physics/CollisionMask.zig");

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

    /// A query in a new frame: the world's tree built over what is in it now, the way the top of a frame builds it
    fn RayCast(self: *TestWorld, ray: PhysicsQueries.Ray, options: PhysicsQueries.QueryOptions) !?PhysicsQueries.PhysicsHit {
        try self.mEngineContext.mEditorWorld.BuildBVH(self.mEngineContext);
        return PhysicsQueries.RayCast(self.mEngineContext, &self.mEngineContext.mEditorWorld, ray, options);
    }

    fn ShapeCast(self: *TestWorld, shape: PhysicsQueries.CastShape, ray: PhysicsQueries.Ray, options: PhysicsQueries.QueryOptions) !?PhysicsQueries.PhysicsHit {
        try self.mEngineContext.mEditorWorld.BuildBVH(self.mEngineContext);
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

test "a ray passes through triggers, other categories and the main object it ignores" {
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
    const only_zero: CollisionMask = .initOne(0);
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

//--------------------------------------------on the world's tree--------------------------------------------

/// The same query by walking the tree and by testing every collider: the same collider, distance and normal
fn ExpectSameAsLinear(world: *TestWorld, shape: PhysicsQueries.CastShape, ray: PhysicsQueries.Ray, options: PhysicsQueries.QueryOptions) !bool {
    const engine_context = world.mEngineContext;
    const by_tree = try PhysicsQueries.ShapeCast(engine_context, &engine_context.mEditorWorld, shape, ray, options);
    const by_testing_all = try PhysicsQueries.ShapeCastLinear(engine_context, &engine_context.mEditorWorld, shape, ray, options);
    try std.testing.expectEqual(by_testing_all == null, by_tree == null);
    const expected = by_testing_all orelse return false;
    const actual = by_tree.?;
    try std.testing.expectEqual(expected.Collider.mID, actual.Collider.mID);
    try std.testing.expectEqual(expected.T, actual.T);
    try std.testing.expectEqual(expected.Normal.x, actual.Normal.x);
    try std.testing.expectEqual(expected.Normal.y, actual.Normal.y);
    try std.testing.expectEqual(expected.Normal.z, actual.Normal.z);
    return true;
}

test "a query on the world's tree hits the same collider as testing every one" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    //spheres and boxes, some turned, rounded, scaled or triggers, in a 30 unit cube
    var prng = std.Random.DefaultPrng.init(0x9E661E);
    const random = prng.random();
    var ignored: Entity = undefined;
    for (0..150) |i| {
        const position = Vec3(f32){ .x = random.float(f32) * 30 - 15, .y = random.float(f32) * 30 - 15, .z = random.float(f32) * 30 - 15 };
        const entity = try world.Collider(if (i % 2 == 0) .Box else .Sphere, position);
        const collider = entity.GetComponent(ColliderComponent).?;
        if (i % 3 == 0) try entity.SetRotation(engine_context, (Vec3(f32){ .x = random.float(f32) * 3, .y = random.float(f32) * 3, .z = random.float(f32) * 3 }).RadiansToQuat());
        if (i % 4 == 0) try entity.SetScale(engine_context, .{ .x = 1 + random.float(f32) * 2, .y = 1 + random.float(f32), .z = 1 });
        if (i % 5 == 0) collider.mCornerRadius = 0.2;
        if (i % 7 == 0) collider.mCollisionFilter.IsTrigger = true;
        if (i == 10) ignored = entity;
    }
    try engine_context.mEditorWorld.BuildBVH(engine_context);

    var hits: usize = 0;
    for (0..300) |i| {
        const origin = Vec3(f32){ .x = random.float(f32) * 40 - 20, .y = random.float(f32) * 40 - 20, .z = random.float(f32) * 40 - 20 };
        //aimed at a point among the colliders, so most rays pass through the crowd
        const target = Vec3(f32){ .x = random.float(f32) * 20 - 10, .y = random.float(f32) * 20 - 10, .z = random.float(f32) * 20 - 10 };
        var dir = target.SubVec(origin);
        dir.Normalize();
        const ray = PhysicsQueries.Ray{ .Origin = origin, .Dir = dir };
        const shape: PhysicsQueries.CastShape = switch (i % 3) {
            0 => .{ .Sphere = 0 },
            1 => .{ .Sphere = 0.1 + random.float(f32) },
            else => .{ .Box = .{ .HalfExtents = .{ .x = 0.3, .y = 0.6, .z = 0.2 }, .Rotation = (Vec3(f32){ .x = 0, .y = 0, .z = 0.7 }).RadiansToQuat() } },
        };
        const options = PhysicsQueries.QueryOptions{
            .MaxDistance = if (i % 4 == 0) 10 else std.math.inf(f32),
            .HitTriggers = i % 5 == 0,
            .Ignore = if (i % 6 == 0) ignored else null,
            .SkipStartedInside = i % 8 != 0,
        };
        if (try ExpectSameAsLinear(world, shape, ray, options)) hits += 1;
    }
    //enough of them hit something to have checked the walk
    try std.testing.expect(hits > 60);
}

test "a query right after something moves finds it where it was moved to, with no new frame" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const editor_world = &engine_context.mEditorWorld;

    const wall = try world.Collider(.Box, .{ .x = 0, .y = 0, .z = 0 });
    _ = try world.Collider(.Box, .{ .x = 0, .y = 50, .z = 0 });
    try editor_world.BuildBVH(engine_context);

    //moved far off the ray, where the tree built this frame doesn't have it
    try wall.SetTranslation(engine_context, .{ .x = 0, .y = 30, .z = 0 });
    try std.testing.expect(try PhysicsQueries.RayCast(engine_context, editor_world, ALONG_X, .{}) == null);

    //and a ray along y through where it is now finds it
    const along_y = PhysicsQueries.Ray{ .Origin = .{ .x = 0, .y = 20, .z = 0 }, .Dir = .{ .x = 0, .y = 1, .z = 0 } };
    const hit = (try PhysicsQueries.RayCast(engine_context, editor_world, along_y, .{})).?;
    try std.testing.expectEqual(wall.mID, hit.Collider.mID);
    try std.testing.expectApproxEqAbs(@as(f32, 9.5), hit.T, eps);
}

test "a query only hits colliders in its own layer" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const hud = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    const game_wall = try world.Collider(.Box, .{ .x = 0, .y = 0, .z = 0 });
    const hud_wall = try hud.CreateEntity(engine_context, Entity.DefaultConfig);
    var collider: ColliderComponent = .{ .mShape = .Box };
    collider.mCollisionFilter.CategoryMask.set(0);
    _ = try hud_wall.AddComponent(engine_context, collider);
    try hud_wall.SetTranslation(engine_context, .{ .x = -2, .y = 0, .z = 0 });

    //the overlay box is nearer along the ray, but it is in canvas units, not the game's
    try std.testing.expectEqual(game_wall.mID, (try world.RayCast(ALONG_X, .{})).?.Collider.mID);
    try std.testing.expectEqual(hud_wall.mID, (try world.RayCast(ALONG_X, .{ .Layer = .OverlayLayer })).?.Collider.mID);
}
