//! Covers the StaticBodyTag/DynamicBodyTag lifecycle and the broad pass split that depends on it.
//! No window and no GPU: BroadPass only pairs entities up, the geometry tests come later.
const std = @import("std");

const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const CollisionManager = @import("CollisionManager.zig");

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const ColliderComponent = EntityComponents.ColliderComponent;
const RigidBodyComponent = EntityComponents.RigidBodyComponent;
const StaticBodyTag = EntityComponents.StaticBodyTag;
const DynamicBodyTag = EntityComponents.DynamicBodyTag;

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

fn MakeBody(engine_context: *EngineContext, scene: Scene, mass: f32) !Entity {
    const entity = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try entity.AddComponent(engine_context, CollidingFilter());
    _ = try entity.AddComponent(engine_context, RigidBodyComponent{});
    if (mass != 0.0) {
        const rigid_body = entity.GetComponent(RigidBodyComponent).?;
        rigid_body.mMass = mass;
        rigid_body._InvMass = 1.0 / mass;
        try entity.SyncBodyTags(engine_context);
    }
    return entity;
}

test "body tags follow _InvMass" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    //a default rigid body has mass 0, so it starts static
    const entity = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try entity.AddComponent(engine_context, RigidBodyComponent{});
    try std.testing.expect(entity.HasComponent(StaticBodyTag));
    try std.testing.expect(!entity.HasComponent(DynamicBodyTag));

    //giving it mass flips it, and the old tag is gone immediately rather than at end of frame
    const rigid_body = entity.GetComponent(RigidBodyComponent).?;
    rigid_body.mMass = 2.0;
    rigid_body._InvMass = 0.5;
    try entity.SyncBodyTags(engine_context);
    try std.testing.expect(entity.HasComponent(DynamicBodyTag));
    try std.testing.expect(!entity.HasComponent(StaticBodyTag));

    //and back again
    rigid_body.mMass = 0.0;
    rigid_body._InvMass = 0.0;
    try entity.SyncBodyTags(engine_context);
    try std.testing.expect(entity.HasComponent(StaticBodyTag));
    try std.testing.expect(!entity.HasComponent(DynamicBodyTag));

    //syncing twice changes nothing
    try entity.SyncBodyTags(engine_context);
    try std.testing.expect(entity.HasComponent(StaticBodyTag));
    try std.testing.expect(!entity.HasComponent(DynamicBodyTag));
}

test "removing the rigid body takes both tags off" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    const entity = try MakeBody(engine_context, scene, 2.0);
    try std.testing.expect(entity.HasComponent(DynamicBodyTag));

    try entity.RemoveComponent(engine_context, RigidBodyComponent);
    try std.testing.expect(!entity.HasComponent(DynamicBodyTag));
    try std.testing.expect(!entity.HasComponent(StaticBodyTag));
}

test "an entity with no rigid body carries neither tag" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    const entity = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try entity.AddComponent(engine_context, CollidingFilter());

    try std.testing.expect(!entity.HasComponent(StaticBodyTag));
    try std.testing.expect(!entity.HasComponent(DynamicBodyTag));
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
    for (0..4) |_| _ = try MakeBody(engine_context, scene, 0.0);

    try collision_manager.BroadPass(engine_context, &engine_context.mEditorWorld);
    try std.testing.expectEqual(@as(usize, 0), collision_manager._BlockingContacts.items.len);

    //one dynamic against those four statics is four pairs, and still nothing static against static
    collision_manager.Reset(engine_context.EngineAllocator());
    _ = try MakeBody(engine_context, scene, 2.0);

    try collision_manager.BroadPass(engine_context, &engine_context.mEditorWorld);
    try std.testing.expectEqual(@as(usize, 4), collision_manager._BlockingContacts.items.len);

    //a second dynamic adds its own four static pairs plus the one dynamic against dynamic pair
    collision_manager.Reset(engine_context.EngineAllocator());
    _ = try MakeBody(engine_context, scene, 3.0);

    try collision_manager.BroadPass(engine_context, &engine_context.mEditorWorld);
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

    //neither body tag, so it can only reach the broad pass through the not-dynamic side
    const bare = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try bare.AddComponent(engine_context, CollidingFilter());

    _ = try MakeBody(engine_context, scene, 2.0);

    try collision_manager.BroadPass(engine_context, &engine_context.mEditorWorld);
    try std.testing.expectEqual(@as(usize, 1), collision_manager._BlockingContacts.items.len);
}

