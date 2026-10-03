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
const MainObjectComponent = EntityComponents.MainObjectComponent;
const ScenePhysicsComponent = @import("../../ECSComponents/SComponents.zig").PhysicsComponent;

const ECSObject = @import("../../ECSObjects/ECSObject.zig");
const ScriptsProcessor = @import("../../Scripts/ScriptsProcessor.zig");

const Vec3 = @import("../../Math/MathTypes.zig").Vec3;
const Quat = @import("../../Math/MathTypes.zig").Quat;
const PhysicsEvent = @import("../../Events/PhysicsEventData.zig").EventT;
const CollisionEndEvent = @import("../../Events/PhysicsEventData.zig").CollisionEndEvent;
const OnCollisionEndScript = EntityComponents.OnCollisionEndScript;
const OnPreSolveScript = EntityComponents.OnPreSolveScript;

const EEventData = @import("../../Events/EManagerData.zig");
const GCEventData = @import("../../Events/GCManagerData.zig");
const PEventData = @import("../../Events/PManagerData.zig");
const SEventData = @import("../../Events/SManagerData.zig");
const ECSEventData = @import("../../Events/ECSEventData.zig");
const EventResult = @import("../../Events/EventManager.zig").EventResult;

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
/// where they are rather than moved by their velocities: transforms, broad, narrow, pre-solve, solve, correct
/// positions, then which pairs touch
fn RunCollisionPasses(collision_manager: *CollisionManager, engine_context: *EngineContext) !void {
    const world_manager = &engine_context.mEditorWorld;
    try PhysicsManager.UpdateWorldTransforms(world_manager, engine_context);

    const groups = try CollisionManager.QueryColliderGroups(world_manager, engine_context.FrameAllocator());
    try collision_manager.BroadPass(engine_context, world_manager, groups);
    collision_manager.NarrowPass(SUBSTEP_DT);
    try collision_manager.PreSolverPass(engine_context, &world_manager.mPhysicsManager.mEventManager);
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

/// Both of the body's friction coefficients. 0 for a test that is about something else sliding along a surface
fn SetFriction(entity: Entity, static: f32, kinetic: f32) void {
    const rigid_body = entity.GetComponent(RigidBodyComponent).?;
    rigid_body.mMaterialData.Surface.Scale.StaticFriction = static;
    rigid_body.mMaterialData.Surface.Scale.KineticFriction = kinetic;
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
    //friction would drag on the sideways speed while the wall stops it
    SetFriction(pair.ball, 0, 0);

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

/// How many of the queued events are of one kind, e.g. only the begins of pairs that have since ended too
fn QueuedCount(engine_context: *EngineContext, kind: std.meta.Tag(PhysicsEvent)) usize {
    var count: usize = 0;
    for (QueuedCollisions(engine_context)) |event| {
        if (event == kind) count += 1;
    }
    return count;
}

/// The queued end events, in the order they were queued
fn QueuedEnds(engine_context: *EngineContext) ![]const CollisionEndEvent {
    var ends: std.ArrayList(CollisionEndEvent) = .empty;
    for (QueuedCollisions(engine_context)) |event| {
        if (event == .CollisionEnd) try ends.append(engine_context.FrameAllocator(), event.CollisionEnd);
    }
    return ends.items;
}

/// Applies the deletes queued this frame, in the same end of frame order as EditorProgram.OnUpdate
fn EndFrame(engine_context: *EngineContext) !void {
    const world = &engine_context.mEditorWorld;
    var callback_list: std.DoublyLinkedList = .{};
    try world.ProcessEvents(SEventData, .EndOfFrame, engine_context, &callback_list);
    try world.ProcessEvents(GCEventData, .EndOfFrame, engine_context, &callback_list);
    try world.ProcessEvents(PEventData, .EndOfFrame, engine_context, &callback_list);
    try world.ProcessEvents(EEventData, .EndOfFrame, engine_context, &callback_list);
    try world.ProcessEvents(ECSEventData, .EndOfFrame, engine_context, &callback_list);
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
    try std.testing.expectEqual(@as(usize, 1), QueuedCount(engine_context, .CollisionBegin));

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
    try std.testing.expectEqual(@as(usize, 1), QueuedCount(engine_context, .CollisionBegin));

    //lifted clear of the wall for a substep, then put back into it
    try pair.ball.SetTranslation(engine_context, .{ .x = -3, .y = 0, .z = 0 });
    try RunSubstep(&collision_manager, engine_context);
    try std.testing.expectEqual(@as(usize, 1), QueuedCount(engine_context, .CollisionBegin));

    try pair.ball.SetTranslation(engine_context, .{ .x = -0.9, .y = 0, .z = 0 });
    try RunSubstep(&collision_manager, engine_context);
    try std.testing.expectEqual(@as(usize, 2), QueuedCount(engine_context, .CollisionBegin));
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

    try std.testing.expectEqual(@as(usize, 1), QueuedCount(engine_context, .CollisionBegin));
    try std.testing.expect(QueuedCollisions(engine_context)[0].CollisionBegin.mIsTrigger);
    try std.testing.expectEqual(@as(f32, -0.9), pair.ball.GetComponent(TransformComponent).?.GetTranslation().x);
}

test "a collision ends once when the pair comes apart, naming the pair that began" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    var collision_manager: CollisionManager = .empty;
    try collision_manager.Init(engine_context.EngineAllocator());
    defer collision_manager.Deinit(engine_context.EngineAllocator());

    const pair = try WallAndBall(engine_context, scene, .{ .x = 0, .y = 0, .z = 0 });

    //still touching is neither a begin nor an end
    try RunSubstep(&collision_manager, engine_context);
    try RunSubstep(&collision_manager, engine_context);
    try std.testing.expectEqual(@as(usize, 0), QueuedCount(engine_context, .CollisionEnd));

    //lifted clear of the wall: it ends on that substep, and staying apart does not end it again
    try pair.ball.SetTranslation(engine_context, .{ .x = -3, .y = 0, .z = 0 });
    try RunSubstep(&collision_manager, engine_context);
    try RunSubstep(&collision_manager, engine_context);

    const ends = try QueuedEnds(engine_context);
    try std.testing.expectEqual(@as(usize, 1), ends.len);
    try std.testing.expectEqual(pair.ball.mID, ends[0].mOrigin.mID);
    try std.testing.expectEqual(pair.wall.mID, ends[0].mTarget.mID);
    try std.testing.expectEqual(pair.ball.mID, ends[0].mOriginCollider.mID);
    try std.testing.expectEqual(pair.wall.mID, ends[0].mTargetCollider.mID);
    try std.testing.expect(!ends[0].mIsTrigger);
}

test "a trigger pair ends once the ball leaves it" {
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
    try pair.ball.SetTranslation(engine_context, .{ .x = -3, .y = 0, .z = 0 });
    try RunSubstep(&collision_manager, engine_context);

    const ends = try QueuedEnds(engine_context);
    try std.testing.expectEqual(@as(usize, 1), ends.len);
    try std.testing.expect(ends[0].mIsTrigger);
}

test "a pair whose filter stops it colliding ends, though the two still overlap" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    var collision_manager: CollisionManager = .empty;
    try collision_manager.Init(engine_context.EngineAllocator());
    defer collision_manager.Deinit(engine_context.EngineAllocator());

    //a trigger, so nothing pushes the ball out and it stays overlapping throughout
    const pair = try WallAndBall(engine_context, scene, .{ .x = 0, .y = 0, .z = 0 });
    pair.wall.GetComponent(ColliderComponent).?.mCollisionFilter.IsTrigger = true;

    try RunSubstep(&collision_manager, engine_context);
    try std.testing.expectEqual(@as(usize, 0), QueuedCount(engine_context, .CollisionEnd));

    //e.g. a Frogger turtle diving: it no longer responds to the frog sitting on it
    pair.wall.GetComponent(ColliderComponent).?.mCollisionFilter.RespondMask.unset(0);
    try RunSubstep(&collision_manager, engine_context);
    try std.testing.expectEqual(@as(usize, 1), QueuedCount(engine_context, .CollisionEnd));
}

test "deleting one side ends its collisions, and only the side still there runs its end scripts" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    var collision_manager: CollisionManager = .empty;
    try collision_manager.Init(engine_context.EngineAllocator());
    defer collision_manager.Deinit(engine_context.EngineAllocator());

    const pair = try WallAndBall(engine_context, scene, .{ .x = 0, .y = 0, .z = 0 });
    //an end script with no asset on the ball: the per type wrapper loads the script to read its type, which
    //needs a built script
    const end_script = try ECSObject.Core(Entity).AddScript(pair.ball, engine_context, .uninit);
    _ = try end_script.AddComponent(engine_context, OnCollisionEndScript{});

    try RunSubstep(&collision_manager, engine_context);

    try pair.wall.Delete(engine_context);
    try EndFrame(engine_context);
    try std.testing.expect(!pair.wall.IsActive());

    try RunSubstep(&collision_manager, engine_context);

    const ends = try QueuedEnds(engine_context);
    try std.testing.expectEqual(@as(usize, 1), ends.len);
    try std.testing.expectEqual(pair.wall.mID, ends[0].mTarget.mID);

    //the wall is gone and is skipped, the ball's script is passed over for having no asset
    try ScriptsProcessor.RunCollisionEndScripts(engine_context, ends[0]);
}

/// How fast a box sliding along a floor of unit tiles side by side is still going after a second, from 3. The seams
/// between tiles are at x = 0.5, 1.5, ... and the box starts on the first tile, 0.8 wide and resting on it
fn SpeedAfterSlidingOverTiles(corner_radius: f32) !f32 {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    _ = try scene.AddComponent(engine_context, ScenePhysicsComponent{});

    for (0..8) |i| {
        const tile = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
        _ = try tile.AddComponent(engine_context, CollidingShape(.Box));
        try tile.SetTranslation(engine_context, .{ .x = @floatFromInt(i), .y = 0, .z = 0 });
    }

    const box = try MakeBall(engine_context, scene, .{ .x = 0, .y = 1, .z = 0 }, .{ .x = 3, .y = 0, .z = 0 });
    const collider = box.GetComponent(ColliderComponent).?;
    collider.mShape = .Box;
    collider.mBoxSize = .{ .x = 0.8, .y = 1, .z = 0.8 };
    collider.mCornerRadius = corner_radius;
    //only the seams should cost it speed
    SetFriction(box, 0, 0);

    for (0..60) |_| try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);
    return VelocityOf(box).x;
}

test "a sharp box catches on the seam between floor tiles, a rounded one rides over it" {
    //sharp, the next tile's corner is a wall straight ahead of it
    try std.testing.expect(try SpeedAfterSlidingOverTiles(0) < 1.6);
    //rounded, each seam is a bump that costs it a little speed, here 3 seams at about 1.5% each
    try std.testing.expect(try SpeedAfterSlidingOverTiles(0.2) > 2.8);
}

test "a turned box dropped on a floor comes to rest on its corner" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    _ = try scene.AddComponent(engine_context, ScenePhysicsComponent{});

    //a floor with its top at y = 0.5
    const floor = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    var floor_collider = CollidingShape(.Box);
    floor_collider.mBoxSize = .{ .x = 10, .y = 1, .z = 10 };
    _ = try floor.AddComponent(engine_context, floor_collider);

    //a unit box turned 45 degrees reaches sqrt(2) / 2 down to its corner. Bodies do not spin yet, so it stays on it
    const box = try MakeBall(engine_context, scene, .{ .x = 0, .y = 3, .z = 0 }, .{ .x = 0, .y = 0, .z = 0 });
    box.GetComponent(ColliderComponent).?.mShape = .Box;
    try box.SetRotation(engine_context, Quat(f32).FromAxisAngle(.{ .x = 0, .y = 0, .z = 1 }, std.math.pi / 4.0));

    for (0..120) |_| try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);

    try std.testing.expectApproxEqAbs(@as(f32, 0.5 + std.math.sqrt1_2), box.GetComponent(TransformComponent).?.GetTranslation().y, 0.02);
    try std.testing.expectApproxEqAbs(@as(f32, 0), VelocityOf(box).y, 0.05);
}

/// A wide floor, a bare collider with its top at y = 0.5 before turning, turned `degrees` about z with a unit box resting
/// on its top turned the same way. How far the box has moved after a second
fn DistanceSlidOnSlope(degrees: f32) !f32 {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    _ = try scene.AddComponent(engine_context, ScenePhysicsComponent{});

    const slope = Quat(f32).FromAxisAngle(.{ .x = 0, .y = 0, .z = 1 }, std.math.degreesToRadians(degrees));

    const floor = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    var floor_collider = CollidingShape(.Box);
    floor_collider.mBoxSize = .{ .x = 20, .y = 1, .z = 20 };
    _ = try floor.AddComponent(engine_context, floor_collider);
    try floor.SetRotation(engine_context, slope);

    //resting on the floor's top: 1 up from its centre, square to the slope. The default friction of 0.6 holds a body on
    //slopes up to atan(0.6), about 31 degrees
    const start = (Vec3(f32){ .x = 0, .y = 1, .z = 0 }).QuatRotate(slope);
    const box = try MakeBall(engine_context, scene, start, .{ .x = 0, .y = 0, .z = 0 });
    box.GetComponent(ColliderComponent).?.mShape = .Box;
    try box.SetRotation(engine_context, slope);

    for (0..60) |_| try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);
    return box.GetComponent(TransformComponent).?.GetTranslation().SubVec(start).Len();
}

test "friction holds a box on a gentle slope and lets it slide down a steep one" {
    try std.testing.expect(try DistanceSlidOnSlope(20) < 0.02);
    //45 degrees slides at g (sin 45 - 0.6 cos 45), about 2.8, which is about 1.4 in a second
    try std.testing.expectApproxEqAbs(@as(f32, 1.39), try DistanceSlidOnSlope(45), 0.1);
}

/// A unit box resting on a bare floor collider with its top at y = 0.5, already moving at `velocity`
fn BoxOnFloor(engine_context: *EngineContext, scene: Scene, velocity: Vec3(f32)) !Entity {
    _ = try scene.AddComponent(engine_context, ScenePhysicsComponent{});
    const floor = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    var floor_collider = CollidingShape(.Box);
    floor_collider.mBoxSize = .{ .x = 100, .y = 1, .z = 100 };
    _ = try floor.AddComponent(engine_context, floor_collider);

    const box = try MakeBall(engine_context, scene, .{ .x = 0, .y = 1, .z = 0 }, velocity);
    box.GetComponent(ColliderComponent).?.mShape = .Box;
    return box;
}

test "kinetic friction slows a sliding box by its coefficient times gravity, and stops it" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    //the floor is a bare collider, which has no say: the box's own 0.5 is the friction
    const box = try BoxOnFloor(engine_context, scene, .{ .x = 3, .y = 0, .z = 0 });
    SetFriction(box, 0.5, 0.5);

    //half a second at 0.5 * 9.81 takes 2.45 off the 3
    for (0..30) |_| try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);
    try std.testing.expectApproxEqAbs(@as(f32, 3.0 - 0.5 * 9.81 * 0.5), VelocityOf(box).x, 0.02);

    //and it comes to a stop rather than turning around
    for (0..30) |_| try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);
    try std.testing.expectApproxEqAbs(@as(f32, 0), VelocityOf(box).x, eps);
}

test "a frictionless surface makes the contact frictionless whatever touches it" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    //ice under a grippy box: the floor gets a static rigid body so it has a material of its own
    const box = try BoxOnFloor(engine_context, scene, .{ .x = 3, .y = 0, .z = 0 });
    SetFriction(box, 1.0, 1.0);
    const floors = try engine_context.mEditorWorld.GetEntityGroup(engine_context.FrameAllocator(), .{ .Component = ColliderComponent });
    for (floors.items) |id| {
        const entity = engine_context.mEditorWorld.GetEntity(id);
        if (entity.mID == box.mID) continue;
        _ = try entity.AddComponent(engine_context, RigidBodyComponent{});
        try entity.SetBodyType(engine_context, StaticBodyTag);
        SetFriction(entity, 0, 0);
    }

    for (0..30) |_| try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);
    try std.testing.expectApproxEqAbs(@as(f32, 3), VelocityOf(box).x, eps);
}

test "friction carries a box along on a moving platform" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    _ = try scene.AddComponent(engine_context, ScenePhysicsComponent{});

    //a kinematic platform moving right at 2 with its top at y = 0.5, and a box at rest on it
    const platform = try MakeMovingBody(engine_context, scene, KinematicBodyTag, .{ .x = 2, .y = 0, .z = 0 });
    var platform_collider = CollidingShape(.Box);
    platform_collider.mBoxSize = .{ .x = 20, .y = 1, .z = 20 };
    _ = try platform.AddComponent(engine_context, platform_collider);

    const box = try MakeBall(engine_context, scene, .{ .x = 0, .y = 1, .z = 0 }, .{ .x = 0, .y = 0, .z = 0 });
    box.GetComponent(ColliderComponent).?.mShape = .Box;

    //0.6 * 9.81 gets it up to the platform's speed in about a third of a second, then static friction holds it there
    for (0..60) |_| try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);
    try std.testing.expectApproxEqAbs(@as(f32, 2), VelocityOf(box).x, eps);
    //the platform is not dragged back by it
    try std.testing.expectApproxEqAbs(@as(f32, 2), VelocityOf(platform).x, eps);
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
    try std.testing.expectEqual(@as(usize, 1), QueuedCount(engine_context, .CollisionBegin));
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
        .mOriginCollider = pair.ball,
        .mTargetCollider = pair.wall,
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
    //a new body is already dynamic, which SetBodyType leaves alone
    try body.SetBodyType(engine_context, body_type_tag);
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
    try std.testing.expectEqual(@as(usize, 1), QueuedCount(engine_context, .CollisionBegin));
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
    try std.testing.expectEqual(@as(usize, 1), QueuedCount(engine_context, .CollisionBegin));
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
    try std.testing.expectEqual(@as(usize, 0), QueuedCount(engine_context, .CollisionBegin));
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
    try std.testing.expectEqual(@as(usize, 1), QueuedCount(engine_context, .CollisionBegin));
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

    try std.testing.expectEqual(@as(usize, 1), QueuedCount(engine_context, .CollisionBegin));
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

    try std.testing.expectEqual(@as(usize, 0), QueuedCount(engine_context, .CollisionBegin));
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

    try std.testing.expectEqual(@as(usize, 1), QueuedCount(engine_context, .CollisionBegin));
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
    return QueuedCount(engine_context, .CollisionBegin);
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

    try std.testing.expectEqual(@as(usize, 1), QueuedCount(engine_context, .CollisionBegin));
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
    try std.testing.expectEqual(@as(usize, 1), QueuedCount(engine_context, .CollisionBegin));
    try std.testing.expect(!QueuedCollisions(engine_context)[0].CollisionBegin.mIsTrigger);
}

/// A dynamic game object at `position` with no collider of its own, and a collider on a convenience child of it
/// at `child_offset`. The child has no MainObjectComponent, so it is part of the parent's body
fn MakeBodyWithChildCollider(engine_context: *EngineContext, scene: Scene, position: Vec3(f32), child_collider: ColliderComponent, child_offset: Vec3(f32)) !struct { body: Entity, collider: Entity } {
    const body = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try body.AddComponent(engine_context, RigidBodyComponent{});
    try body.SetTranslation(engine_context, position);

    const collider = try body.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    _ = try collider.AddComponent(engine_context, child_collider);
    try collider.SetTranslation(engine_context, child_offset);
    return .{ .body = body, .collider = collider };
}

test "two colliders of one game object never collide with each other" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    var collision_manager: CollisionManager = .empty;
    try collision_manager.Init(engine_context.EngineAllocator());
    defer collision_manager.Deinit(engine_context.EngineAllocator());

    //a collider on the object and another on its child, overlapping each other: one body, nothing to collide
    const parts = try MakeBodyWithChildCollider(engine_context, scene, .{ .x = 0, .y = 0, .z = 0 }, CollidingShape(.Box), .{ .x = 0.3, .y = 0, .z = 0 });
    _ = try parts.body.AddComponent(engine_context, CollidingShape(.Box));

    try RunCollisionPasses(&collision_manager, engine_context);
    try std.testing.expectEqual(@as(usize, 0), collision_manager._BlockingContacts.items.len);
    try std.testing.expectEqual(@as(usize, 0), QueuedCount(engine_context, .CollisionBegin));
}

test "a game object whose collider is on a child lands as one body" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    _ = try scene.AddComponent(engine_context, ScenePhysicsComponent{});

    //a floor with its top at y = 0.5
    const floor = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    var floor_collider = CollidingShape(.Box);
    floor_collider.mBoxSize = .{ .x = 10, .y = 1, .z = 10 };
    _ = try floor.AddComponent(engine_context, floor_collider);

    //the object's only collider is a radius 0.25 ball 0.5 below it, so it comes to rest 0.75 above the floor's top
    var feet = CollidingShape(.Sphere);
    feet.mRadius = 0.25;
    const parts = try MakeBodyWithChildCollider(engine_context, scene, .{ .x = 0, .y = 2, .z = 0 }, feet, .{ .x = 0, .y = -0.5, .z = 0 });

    //a second to fall and settle
    for (0..60) |_| try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);

    //the object itself was stopped and moved, its child collider came with it
    try std.testing.expectApproxEqAbs(@as(f32, 1.25), parts.body.GetComponent(TransformComponent).?.GetTranslation().y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), VelocityOf(parts.body).y, 0.001);

    //the event is about the game object, and says which of its colliders touched
    try std.testing.expectEqual(@as(usize, 1), QueuedCount(engine_context, .CollisionBegin));
    const event = QueuedCollisions(engine_context)[0].CollisionBegin;
    try std.testing.expectEqual(parts.body.mID, event.mOrigin.mID);
    try std.testing.expectEqual(parts.collider.mID, event.mOriginCollider.mID);
    try std.testing.expectEqual(floor.mID, event.mTarget.mID);
    try std.testing.expectEqual(floor.mID, event.mTargetCollider.mID);
}

test "a child tagged MainObjectComponent is a game object of its own" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    var collision_manager: CollisionManager = .empty;
    try collision_manager.Init(engine_context.EngineAllocator());
    defer collision_manager.Deinit(engine_context.EngineAllocator());

    //the same overlapping pair as two colliders of one object, but the child is its own game object: a static
    //one, having no rigid body, so the two are a pair like any other
    const parts = try MakeBodyWithChildCollider(engine_context, scene, .{ .x = 0, .y = 0, .z = 0 }, CollidingShape(.Box), .{ .x = 0.9, .y = 0, .z = 0 });
    _ = try parts.body.AddComponent(engine_context, CollidingShape(.Box));
    _ = try parts.collider.AddComponent(engine_context, MainObjectComponent{});

    try RunCollisionPasses(&collision_manager, engine_context);
    try std.testing.expectEqual(@as(usize, 1), collision_manager._BlockingContacts.items.len);
    const contact = collision_manager._BlockingContacts.items[0];
    try std.testing.expectEqual(parts.body.mID, contact.mOriginBody.mID);
    try std.testing.expectEqual(parts.collider.mID, contact.mTargetBody.mID);
}

/// Stands in for the program running OnPhysicsUpdate scripts, which tests can't build: it listens for each physics
/// step beginning, the way the program does, counts them, and pushes `mBody` with `mForce` on each one
const StepListener = struct {
    mSteps: usize = 0,
    mBody: ?Entity = null,
    mForce: Vec3(f32) = .{ .x = 0, .y = 0, .z = 0 },

    fn OnEvent(self: *StepListener, _: *EngineContext, event: *const PhysicsEvent) anyerror!EventResult {
        switch (event.*) {
            .StepBegin => {
                self.mSteps += 1;
                if (self.mBody) |body| body.GetComponent(RigidBodyComponent).?.ApplyForce(self.mForce);
            },
            else => {},
        }
        return .Continue;
    }
};

/// Stands in for the program's pre-solve handler, which runs OnPreSolve scripts: counts the contacts it is handed and
/// decides them by one rule
const PreSolveListener = struct {
    mRule: enum { KeepAll, DropAll, OneWayUp } = .KeepAll,
    mHanded: usize = 0,
    //for OneWayUp, the one way platform
    mPlatform: ?Entity = null,

    fn OnEvent(self: *PreSolveListener, _: *EngineContext, event: *const PhysicsEvent) anyerror!EventResult {
        switch (event.*) {
            .PreSolve => |e| {
                self.mHanded += 1;
                e.mEnabled.* = switch (self.mRule) {
                    .KeepAll => true,
                    .DropAll => false,
                    //the template's one way platform: only something landing on its top, and not something still part
                    //way through it. The event's normal points from origin to target, and the platform can be either,
                    //so it is turned to point from the platform the way RunPreSolveScripts does for a script
                    .OneWayUp => blk: {
                        const from_platform = if (e.mOrigin.mID == self.mPlatform.?.mID) e.mNormal else e.mNormal.Neg();
                        break :blk from_platform.y > 0.7 and e.mSeparation > -0.02;
                    },
                };
            },
            else => {},
        }
        return .Continue;
    }
};

test "a contact switched off before the solver passes through, and does not touch" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    var collision_manager: CollisionManager = .empty;
    try collision_manager.Init(engine_context.EngineAllocator());
    defer collision_manager.Deinit(engine_context.EngineAllocator());

    var listener: PreSolveListener = .{ .mRule = .DropAll };
    engine_context.mEditorWorld.mPhysicsManager.SetSyncCallback(&listener, PreSolveListener.OnEvent);

    const pair = try WallAndBall(engine_context, scene, .{ .x = 5, .y = 0, .z = 0 });
    pair.wall.GetComponent(ColliderComponent).?.mPreSolveEvents = true;

    try RunCollisionPasses(&collision_manager, engine_context);
    try std.testing.expectEqual(@as(usize, 1), listener.mHanded);
    try std.testing.expectEqual(@as(usize, 0), collision_manager._BlockingContacts.items.len);

    //not stopped, not pushed out, and no collision began
    try std.testing.expectApproxEqAbs(@as(f32, 5), VelocityOf(pair.ball).x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, -0.9), pair.ball.GetComponent(TransformComponent).?.GetTranslation().x, eps);
    try std.testing.expectEqual(@as(usize, 0), QueuedCount(engine_context, .CollisionBegin));
}

test "only contacts whose collider asks for it are handed to pre-solve, and kept ones are solved as usual" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    var collision_manager: CollisionManager = .empty;
    try collision_manager.Init(engine_context.EngineAllocator());
    defer collision_manager.Deinit(engine_context.EngineAllocator());

    var listener: PreSolveListener = .{ .mRule = .KeepAll };
    engine_context.mEditorWorld.mPhysicsManager.SetSyncCallback(&listener, PreSolveListener.OnEvent);

    //neither asks
    _ = try WallAndBall(engine_context, scene, .{ .x = 0, .y = 0, .z = 0 });
    try RunSubstep(&collision_manager, engine_context);
    try std.testing.expectEqual(@as(usize, 0), listener.mHanded);

    //the ball asks this time, and the contact it keeps stops it at the wall the same as without pre-solve
    const pair = try WallAndBall(engine_context, scene, .{ .x = 0, .y = 50, .z = 0 });
    try pair.wall.SetTranslation(engine_context, .{ .x = 0, .y = 50, .z = 0 });
    try pair.ball.SetTranslation(engine_context, .{ .x = -0.9, .y = 50, .z = 0 });
    pair.ball.GetComponent(RigidBodyComponent).?.SetVelocity(.{ .x = 5, .y = 0, .z = 0 });
    pair.ball.GetComponent(ColliderComponent).?.mPreSolveEvents = true;

    try RunCollisionPasses(&collision_manager, engine_context);
    try std.testing.expectEqual(@as(usize, 1), listener.mHanded);
    try std.testing.expectApproxEqAbs(@as(f32, 0), VelocityOf(pair.ball).x, eps);
}

test "a one way platform made with pre-solve lets a body jump up through it and land on top" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    _ = try scene.AddComponent(engine_context, ScenePhysicsComponent{});

    var listener: PreSolveListener = .{ .mRule = .OneWayUp };
    engine_context.mEditorWorld.mPhysicsManager.SetSyncCallback(&listener, PreSolveListener.OnEvent);

    //a thin platform with its top at y = 0.1, and a radius 0.5 ball under it jumping up
    const platform = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    var platform_collider = CollidingShape(.Box);
    platform_collider.mBoxSize = .{ .x = 4, .y = 0.2, .z = 4 };
    platform_collider.mPreSolveEvents = true;
    _ = try platform.AddComponent(engine_context, platform_collider);
    listener.mPlatform = platform;

    const ball = try MakeBall(engine_context, scene, .{ .x = 0, .y = -2, .z = 0 }, .{ .x = 0, .y = 10, .z = 0 });

    var highest: f32 = -2;
    for (0..240) |_| {
        try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);
        highest = @max(highest, ball.GetComponent(TransformComponent).?.GetTranslation().y);
    }

    //it went up through the platform, and came down to rest on its top
    try std.testing.expect(listener.mHanded > 0);
    try std.testing.expect(highest > 2);
    try std.testing.expectApproxEqAbs(@as(f32, 0.6), ball.GetComponent(TransformComponent).?.GetTranslation().y, 0.02);
    try std.testing.expectApproxEqAbs(@as(f32, 0), VelocityOf(ball).y, 0.05);
}

test "handing a contact to pre-solve scripts that have nothing to run keeps it" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    const pair = try WallAndBall(engine_context, scene, .{ .x = 0, .y = 0, .z = 0 });
    //a pre-solve script with no asset on the ball, the same as the collision begin test above
    const pre_solve_script = try ECSObject.Core(Entity).AddScript(pair.ball, engine_context, .uninit);
    _ = try pre_solve_script.AddComponent(engine_context, OnPreSolveScript{});

    var enabled = true;
    try ScriptsProcessor.RunPreSolveScripts(engine_context, .{
        .mOrigin = pair.ball,
        .mTarget = pair.wall,
        .mOriginCollider = pair.ball,
        .mTargetCollider = pair.wall,
        .mNormal = .{ .x = 1, .y = 0, .z = 0 },
        .mSeparation = -0.1,
        .mEnabled = &enabled,
    });
    try std.testing.expect(enabled);
}

test "the physics update runs once at the start of every fixed step" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    var listener: StepListener = .{};
    engine_context.mEditorWorld.mPhysicsManager.SetSyncCallback(&listener, StepListener.OnEvent);

    //a frame of exactly one step
    engine_context.mDT = 1.0 / 60.0;
    try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);
    try std.testing.expectEqual(@as(usize, 1), listener.mSteps);

    //a slow frame two and a half steps long: two steps, half a step left over
    engine_context.mDT = 2.5 / 60.0;
    try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);
    try std.testing.expectEqual(@as(usize, 3), listener.mSteps);

    //a fast frame a quarter of a step long: still short of one
    engine_context.mDT = 0.25 / 60.0;
    try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);
    try std.testing.expectEqual(@as(usize, 3), listener.mSteps);
}

test "a force applied as a step begins pushes for the whole step" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    const body = try MakeMovingBody(engine_context, scene, EntityComponents.DynamicBodyTag, .{ .x = 0, .y = 0, .z = 0 });
    try body.SetMass(engine_context, 2);

    var listener: StepListener = .{ .mBody = body, .mForce = .{ .x = 12, .y = 0, .z = 0 } };
    engine_context.mEditorWorld.mPhysicsManager.SetSyncCallback(&listener, StepListener.OnEvent);

    //12 / 2 for the whole 1/60 of a step is 0.1, both substeps. Let go of after each substep, it was half that
    try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);
    try std.testing.expectApproxEqAbs(@as(f32, 0.1), VelocityOf(body).x, eps);

    //pushed again on the next step, because it was applied again
    try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), VelocityOf(body).x, eps);
}

test "a force lasts only for the step it was applied in" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    const body = try MakeMovingBody(engine_context, scene, EntityComponents.DynamicBodyTag, .{ .x = 0, .y = 0, .z = 0 });
    try body.SetMass(engine_context, 2);

    //applied once, the way a once a frame script would: it reaches the next step, and no step after that
    body.GetComponent(RigidBodyComponent).?.ApplyForce(.{ .x = 12, .y = 0, .z = 0 });

    try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);
    try std.testing.expectApproxEqAbs(@as(f32, 0.1), VelocityOf(body).x, eps);

    try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);
    try std.testing.expectApproxEqAbs(@as(f32, 0.1), VelocityOf(body).x, eps);
}

const ConstantForceComponent = EntityComponents.ConstantForceComponent;

test "a constant force pushes a dynamic body every step until it is changed" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    const body = try MakeMovingBody(engine_context, scene, EntityComponents.DynamicBodyTag, .{ .x = 0, .y = 0, .z = 0 });
    try body.SetMass(engine_context, 2);
    _ = try body.AddComponent(engine_context, ConstantForceComponent{ .mForce = .{ .x = 12, .y = 0, .z = 0 } });

    //12 / 2 for a whole 1/60 of a step is 0.1 a step, with nothing applying it again
    try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);
    try std.testing.expectApproxEqAbs(@as(f32, 0.1), VelocityOf(body).x, eps);
    try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), VelocityOf(body).x, eps);

    //switched off, the way a jetpack's input script would on release: the body keeps its speed, and stops gaining
    body.GetComponent(ConstantForceComponent).?.mForce = .{ .x = 0, .y = 0, .z = 0 };
    try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), VelocityOf(body).x, eps);
}

test "a constant force adds up with gravity and with the forces applied for the step" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    _ = try scene.AddComponent(engine_context, ScenePhysicsComponent{ .mGravity = .{ .x = 0, .y = -10, .z = 0 } });

    const body = try MakeMovingBody(engine_context, scene, EntityComponents.DynamicBodyTag, .{ .x = 0, .y = 0, .z = 0 });
    try body.SetMass(engine_context, 2);
    _ = try body.AddComponent(engine_context, ConstantForceComponent{ .mForce = .{ .x = 0, .y = 30, .z = 0 } });

    //the step's own force, the way an OnPhysicsUpdate script would apply it
    var listener: StepListener = .{ .mBody = body, .mForce = .{ .x = 0, .y = 6, .z = 0 } };
    engine_context.mEditorWorld.mPhysicsManager.SetSyncCallback(&listener, StepListener.OnEvent);

    //-10 from gravity, 30 / 2 = 15 from the constant force, 6 / 2 = 3 from the step's: 8 a second, for 1/60 of one
    try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);
    try std.testing.expectApproxEqAbs(@as(f32, 8.0 / 60.0), VelocityOf(body).y, eps);
}

test "a constant force does not move a kinematic body" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    //code alone moves a kinematic body, so it goes on at the speed it was given
    const body = try MakeMovingBody(engine_context, scene, KinematicBodyTag, .{ .x = 1, .y = 0, .z = 0 });
    _ = try body.AddComponent(engine_context, ConstantForceComponent{ .mForce = .{ .x = 0, .y = 50, .z = 0 } });

    try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);
    try std.testing.expectApproxEqAbs(@as(f32, 1), VelocityOf(body).x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 0), VelocityOf(body).y, eps);
}

test "a local constant force turns with the body" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    //a thruster pushing along the body's own x, on a body turned a quarter turn about z: its x is the world's y
    const body = try MakeMovingBody(engine_context, scene, EntityComponents.DynamicBodyTag, .{ .x = 0, .y = 0, .z = 0 });
    try body.SetMass(engine_context, 2);
    try body.SetRotation(engine_context, Quat(f32).FromAxisAngle(.{ .x = 0, .y = 0, .z = 1 }, std.math.pi / 2.0));
    _ = try body.AddComponent(engine_context, ConstantForceComponent{
        .mLocalForce = .{ .x = 12, .y = 0, .z = 0 },
        //and wind in world x, which the turn does not change
        .mForce = .{ .x = 6, .y = 0, .z = 0 },
    });

    try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);
    //12 / 2 up and 6 / 2 along, each for 1/60 of a second
    try std.testing.expectApproxEqAbs(@as(f32, 0.05), VelocityOf(body).x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 0.1), VelocityOf(body).y, eps);
}
