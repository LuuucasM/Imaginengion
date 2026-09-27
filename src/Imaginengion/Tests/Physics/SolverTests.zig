//! Covers the solver pass: what it does to the bodies in a contact once the narrow pass has found it.
//! No window and no GPU, the passes are run by hand in the order PhysicsManager.OnUpdate runs them.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const CollisionManager = @import("../../Physics/CollisionManager.zig");
const PhysicsManager = @import("../../Physics/PhysicsManager.zig");

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const ColliderComponent = EntityComponents.ColliderComponent;
const RigidBodyComponent = EntityComponents.RigidBodyComponent;
const TransformComponent = EntityComponents.TransformComponent;

const Vec3 = @import("../../Math/MathTypes.zig").Vec3;

const eps: f32 = 0.0001;

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

/// A collider of the given shape that responds to everything. The default filter has empty masks,
/// which GetCollisionType reads as never colliding.
fn CollidingShape(shape: ColliderComponent.Shapes) ColliderComponent {
    var component: ColliderComponent = .{ .mShape = shape };
    component.mCollisionFilter.CategoryMask.set(0);
    component.mCollisionFilter.RespondMask.set(0);
    return component;
}

/// A mass 1 sphere at the given spot, already moving
fn MakeBall(engine_context: *EngineContext, scene: Scene, position: Vec3(f32), velocity: Vec3(f32)) !Entity {
    const ball = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try ball.AddComponent(engine_context, CollidingShape(.Sphere));
    _ = try ball.AddComponent(engine_context, RigidBodyComponent{ .mMass = 1.0, ._InvMass = 1.0 });
    try ball.SetTranslation(engine_context, position);
    ball.GetComponent(RigidBodyComponent).?.SetVelocity(velocity);
    return ball;
}

/// The collision half of one physics substep: transforms, broad, narrow, then solve
fn RunCollisionPasses(collision_manager: *CollisionManager, engine_context: *EngineContext) !void {
    const world_manager = &engine_context.mEditorWorld;
    try PhysicsManager.UpdateWorldTransforms(world_manager, engine_context);

    const dynamic_colliders = try world_manager.GetEntityGroup(engine_context.FrameAllocator(), CollisionManager.DynamicCollidersQuery);
    const other_colliders = try world_manager.GetEntityGroup(engine_context.FrameAllocator(), CollisionManager.OtherCollidersQuery);
    try collision_manager.BroadPass(engine_context, world_manager, dynamic_colliders.items, other_colliders.items);
    try collision_manager.NarrowPass(engine_context);
    try collision_manager.SolverPass(world_manager, engine_context);
}

fn ExpectBallStoppedByWall(engine_context: *EngineContext, collision_manager: *CollisionManager, ball: Entity, wall: Entity) !void {
    try RunCollisionPasses(collision_manager, engine_context);
    try std.testing.expectEqual(@as(usize, 1), collision_manager._BlockingContacts.items.len);

    //no restitution yet, so all of the ball's speed into the wall is taken away
    try std.testing.expectApproxEqAbs(@as(f32, 0), ball.GetComponent(RigidBodyComponent).?.GetVelocity().x, eps);

    //the ball is pushed back out the way it came, once: 80% of the 0.1 depth past the 0.01 slop is 0.072.
    //the wall stays where it was
    try std.testing.expectApproxEqAbs(@as(f32, -0.972), ball.GetComponent(TransformComponent).?.GetTranslation().x, eps);
    try std.testing.expectEqual(@as(f32, 0), wall.GetComponent(TransformComponent).?.GetTranslation().x);
}

test "a collider with no rigid body blocks like a static body" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    var collision_manager: CollisionManager = .empty;
    try collision_manager.Init(engine_context.EngineAllocator());
    defer collision_manager.Deinit(engine_context.EngineAllocator());

    //a default box spans 0.5 each way from the origin, so a radius 0.5 ball at -0.9 is 0.1 into it
    const wall = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try wall.AddComponent(engine_context, CollidingShape(.Box));

    const ball = try MakeBall(engine_context, scene, .{ .x = -0.9, .y = 0, .z = 0 }, .{ .x = 5, .y = 0, .z = 0 });

    try ExpectBallStoppedByWall(engine_context, &collision_manager, ball, wall);
}

test "a mass 0 rigid body blocks the same way" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    var collision_manager: CollisionManager = .empty;
    try collision_manager.Init(engine_context.EngineAllocator());
    defer collision_manager.Deinit(engine_context.EngineAllocator());

    const wall = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try wall.AddComponent(engine_context, CollidingShape(.Box));
    _ = try wall.AddComponent(engine_context, RigidBodyComponent{});

    const ball = try MakeBall(engine_context, scene, .{ .x = -0.9, .y = 0, .z = 0 }, .{ .x = 5, .y = 0, .z = 0 });

    try ExpectBallStoppedByWall(engine_context, &collision_manager, ball, wall);
}

/// Gives a body a Custom surface with the given bounce
fn SetRestitution(entity: Entity, restitution: f32) void {
    const rigid_body = entity.GetComponent(RigidBodyComponent).?;
    rigid_body.mMaterialData.Surface.Scale.Restitution = restitution;
}

/// A bare box collider at the origin, 0.5 each way, with a ball already 0.1 into its left face
fn WallAndBall(engine_context: *EngineContext, scene: Scene, velocity: Vec3(f32)) !struct { wall: Entity, ball: Entity } {
    const wall = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try wall.AddComponent(engine_context, CollidingShape(.Box));
    const ball = try MakeBall(engine_context, scene, .{ .x = -0.9, .y = 0, .z = 0 }, velocity);
    return .{ .wall = wall, .ball = ball };
}

test "a new rigid body does not bounce" {
    const body: RigidBodyComponent = .{};
    try std.testing.expectEqual(@as(f32, 0), body.mMaterialData.GetRestitution());
}

test "restitution 1 sends the ball straight back at the same speed" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    var collision_manager: CollisionManager = .empty;
    try collision_manager.Init(engine_context.EngineAllocator());
    defer collision_manager.Deinit(engine_context.EngineAllocator());

    const pair = try WallAndBall(engine_context, scene, .{ .x = 5, .y = 0, .z = 0 });
    SetRestitution(pair.ball, 1.0);

    try RunCollisionPasses(&collision_manager, engine_context);
    const velocity = pair.ball.GetComponent(RigidBodyComponent).?.GetVelocity();
    try std.testing.expectApproxEqAbs(@as(f32, -5), velocity.x, eps);
}

test "restitution 1 at an angle reflects about the normal and keeps the sideways speed" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    var collision_manager: CollisionManager = .empty;
    try collision_manager.Init(engine_context.EngineAllocator());
    defer collision_manager.Deinit(engine_context.EngineAllocator());

    //no friction, so nothing touches the y part: it comes out as a mirror image, the pong bounce
    const pair = try WallAndBall(engine_context, scene, .{ .x = 5, .y = 3, .z = 0 });
    SetRestitution(pair.ball, 1.0);

    try RunCollisionPasses(&collision_manager, engine_context);
    const velocity = pair.ball.GetComponent(RigidBodyComponent).?.GetVelocity();
    try std.testing.expectApproxEqAbs(@as(f32, -5), velocity.x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 3), velocity.y, eps);
}

test "partial restitution hands back that fraction of the closing speed" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    var collision_manager: CollisionManager = .empty;
    try collision_manager.Init(engine_context.EngineAllocator());
    defer collision_manager.Deinit(engine_context.EngineAllocator());

    const pair = try WallAndBall(engine_context, scene, .{ .x = 4, .y = 0, .z = 0 });
    SetRestitution(pair.ball, 0.5);

    try RunCollisionPasses(&collision_manager, engine_context);
    try std.testing.expectApproxEqAbs(@as(f32, -2), pair.ball.GetComponent(RigidBodyComponent).?.GetVelocity().x, eps);
}

test "the bouncier surface wins" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    var collision_manager: CollisionManager = .empty;
    try collision_manager.Init(engine_context.EngineAllocator());
    defer collision_manager.Deinit(engine_context.EngineAllocator());

    //a default, dead ball against a static wall with restitution 1 still bounces fully
    const pair = try WallAndBall(engine_context, scene, .{ .x = 5, .y = 0, .z = 0 });
    _ = try pair.wall.AddComponent(engine_context, RigidBodyComponent{});
    SetRestitution(pair.wall, 1.0);

    try RunCollisionPasses(&collision_manager, engine_context);
    try std.testing.expectApproxEqAbs(@as(f32, -5), pair.ball.GetComponent(RigidBodyComponent).?.GetVelocity().x, eps);
}

test "a slow hit does not bounce" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    var collision_manager: CollisionManager = .empty;
    try collision_manager.Init(engine_context.EngineAllocator());
    defer collision_manager.Deinit(engine_context.EngineAllocator());

    //under the restitution threshold, so even a perfectly bouncy ball just stops, the way a resting one should
    const pair = try WallAndBall(engine_context, scene, .{ .x = 0.5, .y = 0, .z = 0 });
    SetRestitution(pair.ball, 1.0);

    try RunCollisionPasses(&collision_manager, engine_context);
    try std.testing.expectApproxEqAbs(@as(f32, 0), pair.ball.GetComponent(RigidBodyComponent).?.GetVelocity().x, eps);
}
