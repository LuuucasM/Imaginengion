//! Pausing a world's physics (PhysicsManager.SetPaused): no steps while paused, no catching up on the paused time
//! afterwards, and a world copied for play starting unpaused. No window and no GPU.
//! Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
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
        //play mode's copy of the world
        try self.mEngineContext.mSimulateWorld.Init(self.mEngineContext.EngineAllocator());
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mSimulateWorld.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }
};

/// A mass 1 body at the origin, already moving along x. Gravity only pulls on y
fn MakeMovingBody(engine_context: *EngineContext, scene: Scene, velocity_x: f32) !Entity {
    const body = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    //a new rigid body is dynamic with a mass of 1
    _ = try body.AddComponent(engine_context, RigidBodyComponent{});
    body.GetComponent(RigidBodyComponent).?.SetVelocity(.{ .x = velocity_x, .y = 0, .z = 0 });
    return body;
}

fn PositionOf(entity: Entity) Vec3(f32) {
    return entity.GetComponent(TransformComponent).?.GetTranslation();
}

test "a paused world's bodies stand still, and carry on without catching up on the paused time" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const physics = &engine_context.mEditorWorld.mPhysicsManager;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    //6 units a second is 0.1 a step, and every frame here is one step long
    const body = try MakeMovingBody(engine_context, scene, 6);
    try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);
    try std.testing.expectApproxEqAbs(@as(f32, 0.1), PositionOf(body).x, eps);
    const before = PositionOf(body);
    const velocity_before = body.GetComponent(RigidBodyComponent).?.GetVelocity();

    physics.SetPaused(true);
    try std.testing.expect(physics.IsPaused());
    for (0..30) |_| try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);
    //not moved, and not even pulled on by gravity
    try std.testing.expectEqual(before, PositionOf(body));
    try std.testing.expectEqual(velocity_before, body.GetComponent(RigidBodyComponent).?.GetVelocity());

    //one frame after carrying on is one step, not the 30 paused ones as well
    physics.SetPaused(false);
    try engine_context.mEditorWorld.OnPhysicsUpdate(engine_context);
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), PositionOf(body).x, eps);
}

test "a world copied for play starts unpaused, whatever the world it came from" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    //the play world as a game quit while paused left it
    engine_context.mSimulateWorld.mPhysicsManager.SetPaused(true);

    //what pressing play again does
    try engine_context.mEditorWorld.Copy(engine_context, &engine_context.mSimulateWorld);
    try std.testing.expect(!engine_context.mSimulateWorld.mPhysicsManager.IsPaused());
}
