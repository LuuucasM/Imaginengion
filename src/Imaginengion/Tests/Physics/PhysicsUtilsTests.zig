//! Covers PhysicsUtils: Dyn and Kin reaching a body's rigid body from its entity, and an entity with none.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const PhysicsUtils = @import("../../Physics/PhysicsUtils.zig");

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const RigidBodyComponent = EntityComponents.RigidBodyComponent;
const TransformComponent = EntityComponents.TransformComponent;
const KinematicBodyTag = EntityComponents.KinematicBodyTag;

const eps: f32 = 0.0001;

fn InitWorld() !*EngineContext {
    const engine_context = try std.heap.page_allocator.create(EngineContext);
    engine_context.* = .{};
    try engine_context.mEditorWorld.Init(engine_context);
    return engine_context;
}

fn DeinitWorld(engine_context: *EngineContext) void {
    engine_context.mEditorWorld.Deinit(engine_context);
    _ = engine_context._Internal.EngineGPA.deinit();
    std.heap.page_allocator.destroy(engine_context);
}

test "Dyn reaches a dynamic body's velocity and impulses" {
    const engine_context = try InitWorld();
    defer DeinitWorld(engine_context);
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    //a new rigid body is dynamic with a mass of 1
    const body = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try body.AddComponent(engine_context, RigidBodyComponent{});

    PhysicsUtils.Dyn.SetVelocity(body, .{ .x = 1, .y = 0, .z = 0 });
    PhysicsUtils.Dyn.AddVelocity(body, .{ .x = 2, .y = 0, .z = 0 });
    PhysicsUtils.Dyn.ApplyImpulse(body, .{ .x = 4, .y = 0, .z = 0 });
    try std.testing.expectApproxEqAbs(@as(f32, 7), PhysicsUtils.Dyn.GetVelocity(body).?.x, eps);
}

test "Kin.MoveTo moves a kinematic body in the next step" {
    const engine_context = try InitWorld();
    defer DeinitWorld(engine_context);
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    const body = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try body.AddComponent(engine_context, RigidBodyComponent{});
    try body.SetBodyType(engine_context, KinematicBodyTag);

    PhysicsUtils.Kin.MoveTo(body, .{ .x = 1, .y = 0, .z = 0 });
    try engine_context.mEditorWorld.BuildBVH(engine_context);
    try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);
    try std.testing.expectApproxEqAbs(@as(f32, 1), body.GetComponent(TransformComponent).?.GetTranslation().x, eps);
}

test "an entity with no rigid body is left alone" {
    const engine_context = try InitWorld();
    defer DeinitWorld(engine_context);
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    const entity = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    PhysicsUtils.Kin.MoveTo(entity, .{ .x = 1, .y = 0, .z = 0 });
    PhysicsUtils.Dyn.ApplyForce(entity, .{ .x = 1, .y = 0, .z = 0 });
    try std.testing.expect(PhysicsUtils.Kin.GetVelocity(entity) == null);
}
