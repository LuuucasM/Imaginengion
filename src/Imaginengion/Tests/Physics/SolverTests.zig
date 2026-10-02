//! Covers the solver pass: what it does to the bodies in a contact once the narrow pass has found it,
//! the CollisionBeginEvent the narrow pass queues the first substep a pair touches, and handing that
//! event to the entities' collision scripts. Also the gravity each body feels during the step, and how
//! kinematic and static bodies move or don't.
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
const StaticBodyTag = EntityComponents.StaticBodyTag;
const KinematicBodyTag = EntityComponents.KinematicBodyTag;
const ScenePhysicsComponent = @import("../../ECSComponents/SComponents.zig").PhysicsComponent;

const ECSObject = @import("../../ECSObjects/ECSObject.zig");
const ScriptsProcessor = @import("../../Scripts/ScriptsProcessor.zig");

const Vec3 = @import("../../Math/MathTypes.zig").Vec3;
const Quat = @import("../../Math/MathTypes.zig").Quat;
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
    //a new rigid body is dynamic with a mass of 1
    _ = try ball.AddComponent(engine_context, RigidBodyComponent{});
    try ball.SetTranslation(engine_context, position);
    ball.GetComponent(RigidBodyComponent).?.SetVelocity(velocity);
    return ball;
}

/// One physics substep's worth of time, the dt the passes below are run with
const SUBSTEP_DT: f32 = 1.0 / 120.0;

/// The collision half of one physics substep, in the order PhysicsManager.OnUpdate runs it, with the bodies left
/// where they are rather than moved by their velocities: transforms, broad, narrow, solve, correct positions, then
/// which pairs touch
fn RunCollisionPasses(collision_manager: *CollisionManager, engine_context: *EngineContext) !void {
    const world_manager = &engine_context.mEditorWorld;
    try PhysicsManager.UpdateWorldTransforms(world_manager, engine_context);

    const groups = try CollisionManager.QueryColliderGroups(world_manager, engine_context.FrameAllocator());
    try collision_manager.BroadPass(engine_context, world_manager, groups);
    collision_manager.NarrowPass(SUBSTEP_DT);
    collision_manager.SolveVelocities(SUBSTEP_DT);
    collision_manager.SweepTriggers(SUBSTEP_DT);
    try collision_manager.CorrectPositions(world_manager, engine_context);
    //queued where the world's own physics step would queue them, and freed with the world
    try collision_manager.UpdateTouching(engine_context, &world_manager.mPhysicsManager.mEventManager);
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

test "a static rigid body blocks the same way" {
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
    _ = try wall.AddComponent(engine_context, StaticBodyTag{});

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
    _ = try pair.wall.AddComponent(engine_context, StaticBodyTag{});
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

/// A mass 2 body with no collider, at rest, feeling the given share of its scene's gravity. The entity and not
/// its component is handed back: adding the next body can move the component storage under a held pointer
fn MakeFallingBody(engine_context: *EngineContext, scene: Scene, gravity_scale: Vec3(f32)) !Entity {
    const body = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try body.AddComponent(engine_context, RigidBodyComponent{ ._Mass = 2.0, .mGravityScale = gravity_scale });
    return body;
}

fn VelocityOf(body: Entity) Vec3(f32) {
    return body.GetComponent(RigidBodyComponent).?.GetVelocity();
}

test "a body feels its scene's gravity scaled axis by axis" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    _ = try scene.AddComponent(engine_context, ScenePhysicsComponent{ .mGravity = .{ .x = 6, .y = -12, .z = 0 } });

    const as_is = try MakeFallingBody(engine_context, scene, .{ .x = 1, .y = 1, .z = 1 });
    const ignores = try MakeFallingBody(engine_context, scene, .{ .x = 0, .y = 0, .z = 0 });
    const half_down_only = try MakeFallingBody(engine_context, scene, .{ .x = 0, .y = 0.5, .z = 1 });
    const upside_down = try MakeFallingBody(engine_context, scene, .{ .x = 1, .y = -1, .z = 1 });

    //one fixed step is 1/60 s, so each body ends it moving at its scaled gravity / 60, whatever its mass
    try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);

    try std.testing.expectApproxEqAbs(@as(f32, 0.1), VelocityOf(as_is).x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, -0.2), VelocityOf(as_is).y, eps);

    try std.testing.expectApproxEqAbs(@as(f32, 0), VelocityOf(ignores).x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 0), VelocityOf(ignores).y, eps);

    try std.testing.expectApproxEqAbs(@as(f32, 0), VelocityOf(half_down_only).x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, -0.1), VelocityOf(half_down_only).y, eps);

    try std.testing.expectApproxEqAbs(@as(f32, 0.1), VelocityOf(upside_down).x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), VelocityOf(upside_down).y, eps);
}

/// A collider-less body of the given type at the origin, already moving
fn MakeMovingBody(engine_context: *EngineContext, scene: Scene, comptime body_type_tag: type, velocity: Vec3(f32)) !Entity {
    const body = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try body.AddComponent(engine_context, RigidBodyComponent{});
    _ = try body.AddComponent(engine_context, body_type_tag{});
    body.GetComponent(RigidBodyComponent).?.SetVelocity(velocity);
    return body;
}

test "a kinematic body moves by its velocity alone, and a static body not at all" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    //gravity on, which neither of them feels
    _ = try scene.AddComponent(engine_context, ScenePhysicsComponent{});

    const kinematic = try MakeMovingBody(engine_context, scene, KinematicBodyTag, .{ .x = 3, .y = 0, .z = 0 });
    //given a velocity after it is static, the way a script might: it still never moves
    const static = try MakeMovingBody(engine_context, scene, StaticBodyTag, .{ .x = 3, .y = 0, .z = 0 });

    //and nothing pushes the kinematic one: an impulse or a force is lost on it
    kinematic.GetComponent(RigidBodyComponent).?.ApplyImpulse(.{ .x = 100, .y = 0, .z = 0 });
    kinematic.GetComponent(RigidBodyComponent).?.ApplyForce(.{ .x = 100, .y = 0, .z = 0 });

    //one fixed step is 1/60 s
    try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);

    try std.testing.expectApproxEqAbs(@as(f32, 0.05), kinematic.GetComponent(TransformComponent).?.GetTranslation().x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 3), VelocityOf(kinematic).x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 0), VelocityOf(kinematic).y, eps);

    try std.testing.expectEqual(@as(f32, 0), static.GetComponent(TransformComponent).?.GetTranslation().x);
}

test "a kinematic body pushes a dynamic one and is not pushed back" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    var collision_manager: CollisionManager = .empty;
    try collision_manager.Init(engine_context.EngineAllocator());
    defer collision_manager.Deinit(engine_context.EngineAllocator());

    //a paddle-like box at the origin moving right into a ball at rest that is 0.1 into its right face
    const paddle = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try paddle.AddComponent(engine_context, CollidingShape(.Box));
    _ = try paddle.AddComponent(engine_context, RigidBodyComponent{});
    _ = try paddle.AddComponent(engine_context, KinematicBodyTag{});
    paddle.GetComponent(RigidBodyComponent).?.SetVelocity(.{ .x = 2, .y = 0, .z = 0 });

    const ball = try MakeBall(engine_context, scene, .{ .x = 0.9, .y = 0, .z = 0 }, .{ .x = 0, .y = 0, .z = 0 });

    try RunCollisionPasses(&collision_manager, engine_context);

    //no bounce on either, so the ball is carried off at the paddle's speed, and pushed clear by the overlap
    try std.testing.expectApproxEqAbs(@as(f32, 2), VelocityOf(ball).x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 0.972), ball.GetComponent(TransformComponent).?.GetTranslation().x, eps);

    //the paddle goes on as it was, where it was
    try std.testing.expectApproxEqAbs(@as(f32, 2), VelocityOf(paddle).x, eps);
    try std.testing.expectEqual(@as(f32, 0), paddle.GetComponent(TransformComponent).?.GetTranslation().x);
}

/// A wall 0.1 thick across x at the origin, and a small ball (radius 0.1) at x = -1 heading straight at it.
/// At 120 substeps a second a speed of 120 is a whole unit a substep, which used to carry a ball like this
/// clean through the wall without it ever being seen overlapping
fn ThinWallAndFastBall(engine_context: *EngineContext, scene: Scene, speed: f32, restitution: f32) !Entity {
    const wall = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    var wall_collider = CollidingShape(.Box);
    wall_collider.mBoxSize = .{ .x = 0.1, .y = 4, .z = 4 };
    _ = try wall.AddComponent(engine_context, wall_collider);

    const ball = try MakeBall(engine_context, scene, .{ .x = -1, .y = 0, .z = 0 }, .{ .x = speed, .y = 0, .z = 0 });
    ball.GetComponent(ColliderComponent).?.mRadius = 0.1;
    SetRestitution(ball, restitution);
    return ball;
}

test "a fast ball stops at a thin wall instead of passing through it" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    const ball = try ThinWallAndFastBall(engine_context, scene, 120, 0);

    //one fixed step is two substeps. On the first the ball is 0.85 from the wall: it may close that and no more,
    //so it ends with its surface on the wall's (centre at -0.15). On the second it may not close at all
    try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);

    try std.testing.expectApproxEqAbs(@as(f32, -0.15), ball.GetComponent(TransformComponent).?.GetTranslation().x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 0), VelocityOf(ball).x, eps);

    //it was stopped at the surface without ever overlapping, and that is still a collision
    try std.testing.expectEqual(@as(usize, 1), QueuedCollisions(engine_context).len);
}

test "a fast ball bounces off a thin wall's surface, not short of it" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    const ball = try ThinWallAndFastBall(engine_context, scene, 120, 1);

    //first substep: 0.85 to the surface takes 0.85 of the substep, then back out at 120 for the 0.15 left over,
    //which puts it at -0.15 - 0.15 = -0.3. Second substep: a whole unit further back, to -1.3
    try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);

    try std.testing.expectApproxEqAbs(@as(f32, -1.3), ball.GetComponent(TransformComponent).?.GetTranslation().x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, -120), VelocityOf(ball).x, eps);
    try std.testing.expectEqual(@as(usize, 1), QueuedCollisions(engine_context).len);
}

test "a ball sliding past a wall within reach loses no speed and touches nothing" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    //a tall wall with its face at x = 0.5, and a ball 0.015 off it moving straight up alongside: close enough to
    //be a speculative contact, but never closing on the wall
    const wall = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    var wall_collider = CollidingShape(.Box);
    wall_collider.mBoxSize = .{ .x = 1, .y = 10, .z = 10 };
    _ = try wall.AddComponent(engine_context, wall_collider);

    const ball = try MakeBall(engine_context, scene, .{ .x = 1.015, .y = 0, .z = 0 }, .{ .x = 0, .y = 60, .z = 0 });

    try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);

    try std.testing.expectApproxEqAbs(@as(f32, 60), VelocityOf(ball).y, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 0), VelocityOf(ball).x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 1.015), ball.GetComponent(TransformComponent).?.GetTranslation().x, eps);
    try std.testing.expectEqual(@as(usize, 0), QueuedCollisions(engine_context).len);
}

test "a ball resting on a floor stays there and begins touching it once" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    _ = try scene.AddComponent(engine_context, ScenePhysicsComponent{});

    //a floor with its top at y = 0.5, and a radius 0.5 ball sitting exactly on it
    const floor = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    var floor_collider = CollidingShape(.Box);
    floor_collider.mBoxSize = .{ .x = 10, .y = 1, .z = 10 };
    _ = try floor.AddComponent(engine_context, floor_collider);

    const ball = try MakeBall(engine_context, scene, .{ .x = 0, .y = 1, .z = 0 }, .{ .x = 0, .y = 0, .z = 0 });

    //half a second: gravity pulls it into the floor every substep, and the floor stops it every substep
    for (0..30) |_| try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);

    try std.testing.expectApproxEqAbs(@as(f32, 1), ball.GetComponent(TransformComponent).?.GetTranslation().y, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 0), VelocityOf(ball).y, eps);
    //the floor pushes on it every substep, so it never stops touching and never begins again
    try std.testing.expectEqual(@as(usize, 1), QueuedCollisions(engine_context).len);
}

/// A trigger box at `position`, `size` across, so nothing is stopped by it
fn MakeTrigger(engine_context: *EngineContext, scene: Scene, position: Vec3(f32), size: Vec3(f32)) !Entity {
    const trigger = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    var trigger_collider = CollidingShape(.Box);
    trigger_collider.mBoxSize = size;
    trigger_collider.mCollisionFilter.IsTrigger = true;
    _ = try trigger.AddComponent(engine_context, trigger_collider);
    try trigger.SetTranslation(engine_context, position);
    return trigger;
}

/// A ball of radius 0.1 at `position` moving at `velocity`
fn MakeSmallBall(engine_context: *EngineContext, scene: Scene, position: Vec3(f32), velocity: Vec3(f32)) !Entity {
    const ball = try MakeBall(engine_context, scene, position, velocity);
    ball.GetComponent(ColliderComponent).?.mRadius = 0.1;
    return ball;
}

const THIN_TRIGGER = Vec3(f32){ .x = 0.1, .y = 4, .z = 4 };

test "a fast ball that skips a thin trigger is seen crossing it" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    //a unit a substep from -1.5: at -0.5 after the first, at 0.5 after the second. The trigger and the ball
    //only reach 0.15 either side of it, so no snapshot ever has them overlapping
    _ = try MakeTrigger(engine_context, scene, .{ .x = 0, .y = 0, .z = 0 }, THIN_TRIGGER);
    const ball = try MakeSmallBall(engine_context, scene, .{ .x = -1.5, .y = 0, .z = 0 }, .{ .x = 120, .y = 0, .z = 0 });

    try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);

    try std.testing.expectEqual(@as(usize, 1), QueuedCollisions(engine_context).len);
    try std.testing.expect(QueuedCollisions(engine_context)[0].CollisionBegin.mIsTrigger);

    //and a trigger stops nothing
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), ball.GetComponent(TransformComponent).?.GetTranslation().x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 120), VelocityOf(ball).x, eps);
}

test "a fast ball passing beside a trigger is not seen crossing it" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    //the trigger reaches 0.5 up, the ball's path is 0.7 up with a radius of 0.1: 0.1 clear the whole way
    _ = try MakeTrigger(engine_context, scene, .{ .x = 0, .y = 0, .z = 0 }, .{ .x = 0.1, .y = 1, .z = 1 });
    _ = try MakeSmallBall(engine_context, scene, .{ .x = -1.5, .y = 0.7, .z = 0 }, .{ .x = 120, .y = 0, .z = 0 });

    try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);

    try std.testing.expectEqual(@as(usize, 0), QueuedCollisions(engine_context).len);
}

test "a ball that ends a substep inside a trigger begins touching it once" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    //from -1 the first substep's path goes in and stops with the ball's centre on the trigger's. The second
    //substep starts overlapping, which is still the same touch, and leaves; the third is clear of it
    _ = try MakeTrigger(engine_context, scene, .{ .x = 0, .y = 0, .z = 0 }, THIN_TRIGGER);
    _ = try MakeSmallBall(engine_context, scene, .{ .x = -1, .y = 0, .z = 0 }, .{ .x = 120, .y = 0, .z = 0 });

    try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);
    try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);

    try std.testing.expectEqual(@as(usize, 1), QueuedCollisions(engine_context).len);
}

/// How many collisions a fast ball sets off going past a trigger box turned `angle` about z. The ball's path is
/// 0.65 up: clear of the unturned box (0.5 up, plus the radius of 0.1), but into a corner turned 45 degrees,
/// which reaches 0.707 up
fn CrossingsPastTurnedTrigger(angle: f32) !usize {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    const trigger = try MakeTrigger(engine_context, scene, .{ .x = 0, .y = 0, .z = 0 }, ONE_BY_ONE);
    try trigger.SetRotation(engine_context, Quat(f32).FromAxisAngle(.{ .x = 0, .y = 0, .z = 1 }, angle));
    _ = try MakeSmallBall(engine_context, scene, .{ .x = -1.5, .y = 0.65, .z = 0 }, .{ .x = 120, .y = 0, .z = 0 });

    try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);
    return QueuedCollisions(engine_context).len;
}

const ONE_BY_ONE = Vec3(f32){ .x = 1, .y = 1, .z = 1 };

test "a sweep sees a trigger's rotation" {
    try std.testing.expectEqual(@as(usize, 0), try CrossingsPastTurnedTrigger(0));
    try std.testing.expectEqual(@as(usize, 1), try CrossingsPastTurnedTrigger(std.math.pi / 4.0));
}

test "a fast box that skips a thin trigger is seen crossing it" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    //box against box goes through the two boxes added together, here 0.15 either side on x like the ball above
    _ = try MakeTrigger(engine_context, scene, .{ .x = 0, .y = 0, .z = 0 }, THIN_TRIGGER);

    const box = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    var box_collider = CollidingShape(.Box);
    box_collider.mBoxSize = .{ .x = 0.2, .y = 0.2, .z = 0.2 };
    _ = try box.AddComponent(engine_context, box_collider);
    _ = try box.AddComponent(engine_context, RigidBodyComponent{});
    try box.SetTranslation(engine_context, .{ .x = -1.5, .y = 0, .z = 0 });
    box.GetComponent(RigidBodyComponent).?.SetVelocity(.{ .x = 120, .y = 0, .z = 0 });

    try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);

    try std.testing.expectEqual(@as(usize, 1), QueuedCollisions(engine_context).len);
    try std.testing.expect(QueuedCollisions(engine_context)[0].CollisionBegin.mIsTrigger);
}

test "a ball that bounces off a wall does not go into the trigger behind it" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    //a thin wall at the origin with a thin trigger right behind it. The ball would reach the trigger at the
    //speed it comes in at, but it bounces off the wall on the same substep, and the sweep follows the bounce
    const wall = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    var wall_collider = CollidingShape(.Box);
    wall_collider.mBoxSize = THIN_TRIGGER;
    _ = try wall.AddComponent(engine_context, wall_collider);
    _ = try MakeTrigger(engine_context, scene, .{ .x = 0.1, .y = 0, .z = 0 }, THIN_TRIGGER);

    const ball = try MakeSmallBall(engine_context, scene, .{ .x = -1, .y = 0, .z = 0 }, .{ .x = 120, .y = 0, .z = 0 });
    SetRestitution(ball, 1);

    try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);

    //the wall, and only the wall
    try std.testing.expectEqual(@as(usize, 1), QueuedCollisions(engine_context).len);
    try std.testing.expect(!QueuedCollisions(engine_context)[0].CollisionBegin.mIsTrigger);
}
