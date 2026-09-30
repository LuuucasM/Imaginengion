//! Covers the solver pass: what it does to the bodies in a contact once the narrow pass has found it,
//! the CollisionBeginEvent the narrow pass queues the first substep a pair touches, and handing that
//! event to the entities' collision scripts.
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
const OnCollisionBeginScript = EntityComponents.OnCollisionBeginScript;
const OnUpdateScript = EntityComponents.OnUpdateScript;

const ECSObject = @import("../../ECSObjects/ECSObject.zig");
const ScriptsProcessor = @import("../../Scripts/ScriptsProcessor.zig");

const Vec3 = @import("../../Math/MathTypes.zig").Vec3;
const PhysicsEvent = @import("../../Events/PhysicsEventData.zig").EventT;

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
    //queued where the world's own physics step would queue them, and freed with the world
    try collision_manager.NarrowPass(engine_context, &world_manager.mPhysicsManager.mEventManager);
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

/// One whole substep of collision: RunCollisionPasses, then the end pass that empties the contact lists
fn RunSubstep(collision_manager: *CollisionManager, engine_context: *EngineContext) !void {
    try RunCollisionPasses(collision_manager, engine_context);
    collision_manager.EndPass(engine_context);
}

/// The collision events queued so far and not yet cleared
fn QueuedCollisions(engine_context: *EngineContext) []const PhysicsEvent {
    return engine_context.mEditorWorld.mPhysicsManager.mEventManager.mEventsArray.getPtr(.PostPhysics).items;
}

test "a pair's key is the same whichever side comes first" {
    try std.testing.expectEqual(CollisionManager.PairKey(3, 7), CollisionManager.PairKey(7, 3));
    try std.testing.expect(CollisionManager.PairKey(3, 7) != CollisionManager.PairKey(3, 8));
}

test "a collision begins once, and again only after the pair has come apart" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    var collision_manager: CollisionManager = .empty;
    try collision_manager.Init(engine_context.EngineAllocator());
    defer collision_manager.Deinit(engine_context.EngineAllocator());

    const pair = try WallAndBall(engine_context, scene, .{ .x = 0, .y = 0, .z = 0 });

    try RunSubstep(&collision_manager, engine_context);
    try std.testing.expectEqual(@as(usize, 1), QueuedCollisions(engine_context).len);

    //the ball is the dynamic one, so it is the origin, and the wall is to its right
    const event = QueuedCollisions(engine_context)[0].CollisionBegin;
    try std.testing.expectEqual(pair.ball.mID, event.mOrigin.mID);
    try std.testing.expectEqual(pair.wall.mID, event.mTarget.mID);
    try std.testing.expectApproxEqAbs(@as(f32, 1), event.mNormal.x, eps);
    try std.testing.expect(!event.mIsTrigger);

    //the solver leaves the ball a little inside the wall (the slop), so it is still touching on the
    //next substeps, and staying in contact is not a new collision
    try RunSubstep(&collision_manager, engine_context);
    try RunSubstep(&collision_manager, engine_context);
    try std.testing.expectEqual(@as(usize, 1), QueuedCollisions(engine_context).len);

    //lifted clear of the wall for a substep, then put back into it
    try pair.ball.SetTranslation(engine_context, .{ .x = -3, .y = 0, .z = 0 });
    try RunSubstep(&collision_manager, engine_context);
    try std.testing.expectEqual(@as(usize, 1), QueuedCollisions(engine_context).len);

    try pair.ball.SetTranslation(engine_context, .{ .x = -0.9, .y = 0, .z = 0 });
    try RunSubstep(&collision_manager, engine_context);
    try std.testing.expectEqual(@as(usize, 2), QueuedCollisions(engine_context).len);
}

test "a trigger pair begins once too, and is not pushed apart" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    var collision_manager: CollisionManager = .empty;
    try collision_manager.Init(engine_context.EngineAllocator());
    defer collision_manager.Deinit(engine_context.EngineAllocator());

    const pair = try WallAndBall(engine_context, scene, .{ .x = 0, .y = 0, .z = 0 });
    pair.wall.GetComponent(ColliderComponent).?.mCollisionFilter.IsTrigger = true;

    try RunSubstep(&collision_manager, engine_context);
    try RunSubstep(&collision_manager, engine_context);

    try std.testing.expectEqual(@as(usize, 1), QueuedCollisions(engine_context).len);
    try std.testing.expect(QueuedCollisions(engine_context)[0].CollisionBegin.mIsTrigger);
    try std.testing.expectEqual(@as(f32, -0.9), pair.ball.GetComponent(TransformComponent).?.GetTranslation().x);
}

test "a world steps its own physics, and clearing the world forgets who was touching" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const world_manager = &engine_context.mEditorWorld;
    const scene = try world_manager.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    _ = try WallAndBall(engine_context, scene, .{ .x = 0, .y = 0, .z = 0 });

    //the default frame time is exactly one fixed step, which is two substeps: the pair begins on the
    //first and is only still touching on the second
    try world_manager.OnPhysicsUpdate(engine_context);
    try std.testing.expectEqual(@as(usize, 1), QueuedCollisions(engine_context).len);
    try std.testing.expectEqual(@as(usize, 1), world_manager.mPhysicsManager._CollisionManager._TouchingLast.items.len);

    //another world's physics has seen none of it
    try std.testing.expectEqual(@as(usize, 0), engine_context.mGameWorld.mPhysicsManager._CollisionManager._TouchingLast.items.len);

    world_manager.clearAndFree(engine_context, .All);
    try std.testing.expectEqual(@as(usize, 0), world_manager.mPhysicsManager._CollisionManager._TouchingLast.items.len);
}

test "handing a collision to scripts that have nothing to run is skipped" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    const pair = try WallAndBall(engine_context, scene, .{ .x = 0, .y = 0, .z = 0 });

    //a collision script and one of another type on the ball. Core's AddScript with no asset: the per
    //type wrapper loads the script to read its type, which needs a built script
    const collision_script = try ECSObject.Core(Entity).AddScript(pair.ball, engine_context, .uninit);
    _ = try collision_script.AddComponent(engine_context, OnCollisionBeginScript{});
    const update_script = try ECSObject.Core(Entity).AddScript(pair.ball, engine_context, .uninit);
    _ = try update_script.AddComponent(engine_context, OnUpdateScript{});

    //the update script is passed over for not being a collision script, the collision script for
    //having no asset, and the wall for having no scripts at all
    try ScriptsProcessor.RunCollisionBeginScripts(engine_context, .{
        .mOrigin = pair.ball,
        .mTarget = pair.wall,
        .mNormal = .{ .x = 1, .y = 0, .z = 0 },
        .mIsTrigger = false,
    });
}
