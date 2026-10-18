//! The broad pass on the world's tree (CollisionManager.BroadPass), checked against trying every pair
//! (BroadPassLinear). No window or GPU. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const CollisionManager = @import("../../Physics/CollisionManager.zig");
const SUB_STEP_DT = @import("../../Physics/PhysicsManager.zig").SUB_STEP_DT;
const Vec3 = @import("../../Math/MathTypes.zig").Vec3;

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const ColliderComponent = EntityComponents.ColliderComponent;
const RigidBodyComponent = EntityComponents.RigidBodyComponent;
const KinematicBodyTag = EntityComponents.KinematicBodyTag;
const StaticBodyTag = EntityComponents.StaticBodyTag;

const TestWorld = struct {
    mEngineContext: *EngineContext,

    fn Init() !*TestWorld {
        const self = try std.heap.page_allocator.create(TestWorld);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        self.mEngineContext.* = .{};
        try self.mEngineContext.mEditorWorld.Init(self.mEngineContext.EngineAllocator());
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        engine_context.mEditorWorld.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }
};

const BodyType = enum { Dynamic, Kinematic, Static, NoBody };

/// A collider that collides with everything on layer 0, on a body of `body_type`, at `position` moving at `velocity`
fn MakeCollider(engine_context: *EngineContext, scene: Scene, shape: ColliderComponent.Shapes, body_type: BodyType, position: Vec3(f32), velocity: Vec3(f32)) !Entity {
    const entity = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    var collider: ColliderComponent = .{ .mShape = shape };
    collider.mCollisionFilter.CategoryMask.set(0);
    collider.mCollisionFilter.RespondMask.set(0);
    _ = try entity.AddComponent(engine_context, collider);
    try entity.SetTranslation(engine_context, position);
    if (body_type == .NoBody) return entity;

    _ = try entity.AddComponent(engine_context, RigidBodyComponent{});
    switch (body_type) {
        .Dynamic => {},
        .Kinematic => try entity.SetBodyType(engine_context, KinematicBodyTag),
        .Static => try entity.SetBodyType(engine_context, StaticBodyTag),
        .NoBody => unreachable,
    }
    entity.GetComponent(RigidBodyComponent).?.SetVelocity(velocity);
    return entity;
}

/// Every pair a broad pass followed by the narrow pass keeps, by PairKey, solid ones and trigger ones apart
const Kept = struct {
    Blocking: std.ArrayList(u64) = .empty,
    Overlap: std.ArrayList(u64) = .empty,

    fn Deinit(self: *Kept) void {
        self.Blocking.deinit(std.testing.allocator);
        self.Overlap.deinit(std.testing.allocator);
    }
};

/// Runs a broad pass (the tree's or the linear one) and the narrow pass on the world as it is, and what they kept
fn KeptPairs(engine_context: *EngineContext, comptime linear: bool) !Kept {
    const world_manager = &engine_context.mEditorWorld;
    try world_manager.BuildBVH(engine_context);
    const groups = try CollisionManager.QueryColliderGroups(world_manager, engine_context.FrameAllocator());

    var collision_manager: CollisionManager = .empty;
    defer collision_manager.Deinit(engine_context.EngineAllocator());
    if (linear) {
        try collision_manager.BroadPassLinear(engine_context, world_manager, groups);
    } else {
        try collision_manager.BroadPass(engine_context, world_manager, groups);
    }
    collision_manager.NarrowPass(SUB_STEP_DT);

    var kept = Kept{};
    for (collision_manager._BlockingContacts.items) |contact| try kept.Blocking.append(std.testing.allocator, CollisionManager.PairKey(contact.mOrigin.mID, contact.mTarget.mID));
    for (collision_manager._OverlapContacts.items) |contact| try kept.Overlap.append(std.testing.allocator, CollisionManager.PairKey(contact.mOrigin.mID, contact.mTarget.mID));
    std.sort.pdq(u64, kept.Blocking.items, {}, std.sort.asc(u64));
    std.sort.pdq(u64, kept.Overlap.items, {}, std.sort.asc(u64));
    return kept;
}

/// How many pairs the broad pass alone hands over
fn BroadPairCount(engine_context: *EngineContext) !usize {
    const world_manager = &engine_context.mEditorWorld;
    try world_manager.BuildBVH(engine_context);
    const groups = try CollisionManager.QueryColliderGroups(world_manager, engine_context.FrameAllocator());
    var collision_manager: CollisionManager = .empty;
    defer collision_manager.Deinit(engine_context.EngineAllocator());
    try collision_manager.BroadPass(engine_context, world_manager, groups);
    return collision_manager._BlockingContacts.items.len + collision_manager._OverlapContacts.items.len;
}

test "the tree's broad pass leaves the narrow pass the same pairs as trying every pair" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const level = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    //bodies of every kind crowded into a small space, some moving fast enough to reach a neighbour within the substep
    //only by their speed, some of them triggers
    var prng = std.Random.DefaultPrng.init(0xB40AD);
    const random = prng.random();
    for (0..120) |i| {
        const position = Vec3(f32){ .x = random.float(f32) * 16 - 8, .y = random.float(f32) * 16 - 8, .z = random.float(f32) * 2 - 1 };
        const speed: f32 = if (i % 4 == 0) 200 else 3;
        const velocity = Vec3(f32){ .x = (random.float(f32) * 2 - 1) * speed, .y = (random.float(f32) * 2 - 1) * speed, .z = 0 };
        const body_type: BodyType = switch (i % 5) {
            0, 1 => .Dynamic,
            2 => .Kinematic,
            3 => .Static,
            else => .NoBody,
        };
        const shape: ColliderComponent.Shapes = if (i % 2 == 0) .Sphere else .Box;
        const entity = try MakeCollider(engine_context, level, shape, body_type, position, velocity);
        if (i % 7 == 0) entity.GetComponent(ColliderComponent).?.mCollisionFilter.IsTrigger = true;
    }

    var by_tree = try KeptPairs(engine_context, false);
    defer by_tree.Deinit();
    var by_trying_all = try KeptPairs(engine_context, true);
    defer by_trying_all.Deinit();

    //the scene really does have pairs of both kinds to find
    try std.testing.expect(by_trying_all.Blocking.items.len > 10);
    try std.testing.expect(by_trying_all.Overlap.items.len > 2);
    try std.testing.expectEqualSlices(u64, by_trying_all.Blocking.items, by_tree.Blocking.items);
    try std.testing.expectEqualSlices(u64, by_trying_all.Overlap.items, by_tree.Overlap.items);
}

test "two dynamic bodies make one pair, and a far one makes none" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const level = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const zero = Vec3(f32){ .x = 0, .y = 0, .z = 0 };

    _ = try MakeCollider(engine_context, level, .Sphere, .Dynamic, zero, zero);
    _ = try MakeCollider(engine_context, level, .Sphere, .Dynamic, .{ .x = 0.5, .y = 0, .z = 0 }, zero);
    _ = try MakeCollider(engine_context, level, .Sphere, .Dynamic, .{ .x = 50, .y = 0, .z = 0 }, zero);

    try std.testing.expectEqual(@as(usize, 1), try BroadPairCount(engine_context));
}

test "a game collider and an overlay collider in the same spot never pair" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const level = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const hud = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    const zero = Vec3(f32){ .x = 0, .y = 0, .z = 0 };

    _ = try MakeCollider(engine_context, level, .Sphere, .Dynamic, zero, zero);
    _ = try MakeCollider(engine_context, hud, .Sphere, .Dynamic, zero, zero);
    try std.testing.expectEqual(@as(usize, 0), try BroadPairCount(engine_context));

    //each with a partner in its own layer, it pairs with that
    _ = try MakeCollider(engine_context, level, .Sphere, .Static, zero, zero);
    _ = try MakeCollider(engine_context, hud, .Sphere, .Static, zero, zero);
    try std.testing.expectEqual(@as(usize, 2), try BroadPairCount(engine_context));
}

test "two bodies closing fast are paired while still apart, by how far each can reach this substep" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const level = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    //two radius 0.5 spheres 3 apart, a gap of 2: at 120 each towards the other they close 2 in one substep (1/120 s)
    const left = try MakeCollider(engine_context, level, .Sphere, .Dynamic, .{ .x = -1.5, .y = 0, .z = 0 }, .{ .x = 120, .y = 0, .z = 0 });
    const right = try MakeCollider(engine_context, level, .Sphere, .Dynamic, .{ .x = 1.5, .y = 0, .z = 0 }, .{ .x = -120, .y = 0, .z = 0 });
    try std.testing.expectEqual(@as(usize, 1), try BroadPairCount(engine_context));

    //standing still, the same gap is too far to pair
    for ([_]Entity{ left, right }) |body| body.GetComponent(RigidBodyComponent).?.SetVelocity(.{ .x = 0, .y = 0, .z = 0 });
    try std.testing.expectEqual(@as(usize, 0), try BroadPairCount(engine_context));
}
