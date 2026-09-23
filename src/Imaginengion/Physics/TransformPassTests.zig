//! Reproduces the editor sequence (new scene -> new entity -> move its transform) against the
//! transform pass, with no window and no renderer. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../Core/EngineContext.zig");
const WorldManager = @import("../Core/WorldManager.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const PhysicsManager = @import("PhysicsManager.zig");

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const TransformComponent = EntityComponents.TransformComponent;
const TransformDirtyTag = EntityComponents.TransformDirtyTag;

const MathTypes = @import("../Math/MathTypes.zig");
const Vec3 = MathTypes.Vec3;

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

fn ExpectFinite(v: Vec3(f32), label: []const u8) !void {
    if (!std.math.isFinite(v.x) or !std.math.isFinite(v.y) or !std.math.isFinite(v.z)) {
        std.debug.print("\n{s} is not finite: {d} {d} {d}\n", .{ label, v.x, v.y, v.z });
        return error.NonFiniteTransform;
    }
}

test "scene, entity, move transform: world transform stays sane" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const entity = try scene.CreateEntity(engine_context, Entity.DefaultConfig);

    try std.testing.expect(entity.HasComponent(TransformComponent));
    //adding the transform should have tagged it, via Manager.AddComponent
    try std.testing.expect(entity.HasComponent(TransformDirtyTag));

    try PhysicsManager.UpdateWorldTransforms(.Editor, engine_context);
    try std.testing.expect(!entity.HasComponent(TransformDirtyTag));

    const t0 = entity.GetComponent(TransformComponent).?;
    try ExpectFinite(t0.GetWorldPosition(), "world position");
    try ExpectFinite(t0.GetWorldScale(), "world scale");

    //now move it, the way the components panel does
    try entity.SetTranslation(engine_context, .{ .x = 3.0, .y = 0.0, .z = 0.0 });
    try std.testing.expect(entity.HasComponent(TransformDirtyTag));

    try PhysicsManager.UpdateWorldTransforms(.Editor, engine_context);

    const t1 = entity.GetComponent(TransformComponent).?;
    try ExpectFinite(t1.GetWorldPosition(), "world position after move");
    try ExpectFinite(t1.GetWorldScale(), "world scale after move");
    try std.testing.expectEqual(@as(f32, 3.0), t1.GetWorldPosition().x);
}

test "repeated moves do not drift the world scale" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const entity = try scene.CreateEntity(engine_context, Entity.DefaultConfig);

    try PhysicsManager.UpdateWorldTransforms(.Editor, engine_context);
    const first_scale = entity.GetComponent(TransformComponent).?.GetWorldScale();

    //the panel tags every frame it is open, so this is the steady state while dragging a value
    for (0..60) |i| {
        try entity.SetTranslation(engine_context, .{ .x = @floatFromInt(i), .y = 0, .z = 0 });
        try PhysicsManager.UpdateWorldTransforms(.Editor, engine_context);
    }

    const last = entity.GetComponent(TransformComponent).?;
    try ExpectFinite(last.GetWorldScale(), "world scale after 60 moves");
    try ExpectFinite(last.GetWorldPosition(), "world position after 60 moves");
    try std.testing.expectEqual(first_scale.x, last.GetWorldScale().x);
    try std.testing.expectEqual(@as(f32, 59.0), last.GetWorldPosition().x);
}
