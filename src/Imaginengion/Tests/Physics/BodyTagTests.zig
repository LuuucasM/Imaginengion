//! Covers the body type tags: a rigid body carries exactly one, which is the record of its type, its mass
//! is kept at the minimum or above, and the broad pass pairs bodies by type.
//! No window and no GPU: BroadPass only pairs entities up, the geometry tests come later.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const CollisionManager = @import("../../Physics/CollisionManager.zig");

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const ColliderComponent = EntityComponents.ColliderComponent;
const RigidBodyComponent = EntityComponents.RigidBodyComponent;
const StaticBodyTag = EntityComponents.StaticBodyTag;
const KinematicBodyTag = EntityComponents.KinematicBodyTag;
const DynamicBodyTag = EntityComponents.DynamicBodyTag;

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

/// A collider that responds to everything. The default filter has empty masks, which
/// GetCollisionType reads as never colliding, so a default collider would make every test trivial.
fn CollidingFilter() ColliderComponent {
    var component: ColliderComponent = .{};
    component.mCollisionFilter.CategoryMask.set(0);
    component.mCollisionFilter.RespondMask.set(0);
    return component;
}

/// A collider with a rigid body of the given type
fn MakeBody(engine_context: *EngineContext, scene: Scene, comptime body_type_tag: type) !Entity {
    const entity = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try entity.AddComponent(engine_context, CollidingFilter());
    _ = try entity.AddComponent(engine_context, RigidBodyComponent{});
    //a new body is already dynamic, which SetBodyType leaves alone
    try entity.SetBodyType(engine_context, body_type_tag);
    return entity;
}

/// Which of the type tags the entity carries, and that it is only the one
fn ExpectOnlyType(entity: Entity, comptime body_type_tag: type) !void {
    inline for (Entity.BodyTypeTags) |tag_type| {
        try std.testing.expectEqual(tag_type == body_type_tag, entity.HasComponent(tag_type));
    }
}

/// Queries the collider groups the way PhysicsManager.OnUpdate does, then runs the broad pass on them
fn RunBroadPass(collision_manager: *CollisionManager, engine_context: *EngineContext) !void {
    const world_manager = &engine_context.mEditorWorld;
    const groups = try CollisionManager.QueryColliderGroups(world_manager, engine_context.FrameAllocator());
    try collision_manager.BroadPass(engine_context, world_manager, groups);
}

test "a new rigid body is dynamic with a mass of 1" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    const entity = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try entity.AddComponent(engine_context, RigidBodyComponent{});

    try ExpectOnlyType(entity, DynamicBodyTag);
    const rigid_body = entity.GetComponent(RigidBodyComponent).?;
    try std.testing.expectEqual(@as(f32, 1), rigid_body.GetMass());
    try std.testing.expectEqual(@as(f32, 1), rigid_body._InvMass);
}

test "a rigid body with no type and no mass is made static" {
    //how a file saved a static body before there were body types
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    const entity = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try entity.AddComponent(engine_context, RigidBodyComponent{ ._Mass = 0 });

    try ExpectOnlyType(entity, StaticBodyTag);
    const rigid_body = entity.GetComponent(RigidBodyComponent).?;
    try std.testing.expectEqual(RigidBodyComponent.MIN_MASS, rigid_body.GetMass());
    try std.testing.expectEqual(@as(f32, 0), rigid_body._InvMass);
}

test "adding a type tag replaces the body's type, and only a dynamic body can be pushed" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    const entity = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try entity.AddComponent(engine_context, RigidBodyComponent{ ._Mass = 4 });

    //the old tag is gone at once rather than at end of frame
    _ = try entity.AddComponent(engine_context, KinematicBodyTag{});
    try ExpectOnlyType(entity, KinematicBodyTag);
    try std.testing.expectEqual(@as(f32, 0), entity.GetComponent(RigidBodyComponent).?._InvMass);

    //a static body keeps no velocity: it never moves
    entity.GetComponent(RigidBodyComponent).?.SetVelocity(.{ .x = 3, .y = 0, .z = 0 });
    _ = try entity.AddComponent(engine_context, StaticBodyTag{});
    try ExpectOnlyType(entity, StaticBodyTag);
    try std.testing.expectEqual(@as(f32, 0), entity.GetComponent(RigidBodyComponent).?._InvMass);
    try std.testing.expectEqual(@as(f32, 0), entity.GetComponent(RigidBodyComponent).?.GetVelocity().x);

    //the mass was kept all along, it is only used once the body is dynamic
    _ = try entity.AddComponent(engine_context, DynamicBodyTag{});
    try ExpectOnlyType(entity, DynamicBodyTag);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), entity.GetComponent(RigidBodyComponent).?._InvMass, eps);
}

test "a mass never goes below the minimum" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    //the type tag first, the way a file can list it ahead of the rigid body: the tag waits for the body,
    //and the body's mass is brought up to the minimum when it arrives
    const entity = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try entity.AddComponent(engine_context, DynamicBodyTag{});
    _ = try entity.AddComponent(engine_context, RigidBodyComponent{ ._Mass = -1 });
    try ExpectOnlyType(entity, DynamicBodyTag);
    try std.testing.expectEqual(RigidBodyComponent.MIN_MASS, entity.GetComponent(RigidBodyComponent).?.GetMass());

    try entity.SetMass(engine_context, 0);
    try std.testing.expectEqual(RigidBodyComponent.MIN_MASS, entity.GetComponent(RigidBodyComponent).?.GetMass());

    try entity.SetMass(engine_context, 4);
    try std.testing.expectEqual(@as(f32, 4), entity.GetComponent(RigidBodyComponent).?.GetMass());
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), entity.GetComponent(RigidBodyComponent).?._InvMass, eps);

    //a write straight into the field is caught the next time the body is synced, as the editor's input is
    entity.GetComponent(RigidBodyComponent).?._Mass = -5;
    try entity.SyncRigidBody(engine_context);
    try std.testing.expectEqual(RigidBodyComponent.MIN_MASS, entity.GetComponent(RigidBodyComponent).?.GetMass());
}

test "removing the rigid body takes its type tag off" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    const entity = try MakeBody(engine_context, scene, KinematicBodyTag);
    try ExpectOnlyType(entity, KinematicBodyTag);

    try entity.RemoveComponent(engine_context, RigidBodyComponent);
    try std.testing.expect(!entity.HasBodyTypeTag());
}

test "an entity with no rigid body carries no type tag" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    const entity = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try entity.AddComponent(engine_context, CollidingFilter());

    try std.testing.expect(!entity.HasBodyTypeTag());
}

test "BroadPass skips pairs that neither side can move" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    var collision_manager: CollisionManager = .empty;
    try collision_manager.Init(engine_context.EngineAllocator());
    defer collision_manager.Deinit(engine_context.EngineAllocator());

    //four statics: six pairs, none of which the solver could ever act on
    for (0..4) |_| _ = try MakeBody(engine_context, scene, StaticBodyTag);

    try RunBroadPass(&collision_manager, engine_context);
    try std.testing.expectEqual(@as(usize, 0), collision_manager._BlockingContacts.items.len);

    //one dynamic against those four statics is four pairs, and still nothing static against static
    collision_manager.Reset(engine_context.EngineAllocator());
    _ = try MakeBody(engine_context, scene, DynamicBodyTag);

    try RunBroadPass(&collision_manager, engine_context);
    try std.testing.expectEqual(@as(usize, 4), collision_manager._BlockingContacts.items.len);

    //a second dynamic adds its own four static pairs plus the one dynamic against dynamic pair
    collision_manager.Reset(engine_context.EngineAllocator());
    _ = try MakeBody(engine_context, scene, DynamicBodyTag);

    try RunBroadPass(&collision_manager, engine_context);
    try std.testing.expectEqual(@as(usize, 9), collision_manager._BlockingContacts.items.len);
}

test "a collider with no rigid body still takes part in the broad pass" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    var collision_manager: CollisionManager = .empty;
    try collision_manager.Init(engine_context.EngineAllocator());
    defer collision_manager.Deinit(engine_context.EngineAllocator());

    //no body type tag, so it can only reach the broad pass as a static collider
    const bare = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try bare.AddComponent(engine_context, CollidingFilter());

    _ = try MakeBody(engine_context, scene, DynamicBodyTag);

    try RunBroadPass(&collision_manager, engine_context);
    try std.testing.expectEqual(@as(usize, 1), collision_manager._BlockingContacts.items.len);
}

test "a kinematic body pairs with a dynamic one always, and with static and kinematic ones only through a trigger" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    var collision_manager: CollisionManager = .empty;
    try collision_manager.Init(engine_context.EngineAllocator());
    defer collision_manager.Deinit(engine_context.EngineAllocator());

    //a solid kinematic against a solid static and a solid kinematic: nothing can be pushed and nothing is a
    //trigger, so no pairs at all
    _ = try MakeBody(engine_context, scene, KinematicBodyTag);
    const static_body = try MakeBody(engine_context, scene, StaticBodyTag);
    const other_kinematic = try MakeBody(engine_context, scene, KinematicBodyTag);

    try RunBroadPass(&collision_manager, engine_context);
    try std.testing.expectEqual(@as(usize, 0), collision_manager._BlockingContacts.items.len);
    try std.testing.expectEqual(@as(usize, 0), collision_manager._OverlapContacts.items.len);

    //the static one becomes a zone: both kinematic bodies pair with it, as overlaps
    collision_manager.Reset(engine_context.EngineAllocator());
    static_body.GetComponent(ColliderComponent).?.mCollisionFilter.IsTrigger = true;

    try RunBroadPass(&collision_manager, engine_context);
    try std.testing.expectEqual(@as(usize, 0), collision_manager._BlockingContacts.items.len);
    try std.testing.expectEqual(@as(usize, 2), collision_manager._OverlapContacts.items.len);

    //one kinematic body a trigger too: it now also pairs with the other kinematic one
    collision_manager.Reset(engine_context.EngineAllocator());
    other_kinematic.GetComponent(ColliderComponent).?.mCollisionFilter.IsTrigger = true;

    try RunBroadPass(&collision_manager, engine_context);
    try std.testing.expectEqual(@as(usize, 3), collision_manager._OverlapContacts.items.len);

    //a dynamic body pairs with all three whatever they are: two of them are triggers, the first kinematic is solid
    collision_manager.Reset(engine_context.EngineAllocator());
    _ = try MakeBody(engine_context, scene, DynamicBodyTag);

    try RunBroadPass(&collision_manager, engine_context);
    try std.testing.expectEqual(@as(usize, 1), collision_manager._BlockingContacts.items.len);
    try std.testing.expectEqual(@as(usize, 3 + 2), collision_manager._OverlapContacts.items.len);
}
