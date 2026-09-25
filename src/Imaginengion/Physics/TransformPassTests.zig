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
const MainObjectComponent = @import("../ECS/Components.zig").MainObjectComponent;

const MathTypes = @import("../Math/MathTypes.zig");
const Vec3 = MathTypes.Vec3;
const Quat = MathTypes.Quat;

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

fn ExpectVec3Near(expected: Vec3(f32), actual: Vec3(f32)) !void {
    try std.testing.expectApproxEqAbs(expected.x, actual.x, 0.0001);
    try std.testing.expectApproxEqAbs(expected.y, actual.y, 0.0001);
    try std.testing.expectApproxEqAbs(expected.z, actual.z, 0.0001);
}

fn ZRotation(degrees: f32) Quat(f32) {
    return Quat(f32).FromAxisAngle(.{ .x = 0, .y = 0, .z = 1 }, std.math.degreesToRadians(degrees));
}

test "a child swings around a turning parent" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const parent = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    const child = try parent.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    try child.SetTranslation(engine_context, .{ .x = 2, .y = 0, .z = 0 });

    //a quarter turn about z takes the child's arm from +x round to +y
    try parent.SetRotation(engine_context, ZRotation(90));
    try PhysicsManager.UpdateWorldTransforms(.Editor, engine_context);

    const child_transform = child.GetComponent(TransformComponent).?;
    try ExpectVec3Near(.{ .x = 0, .y = 2, .z = 0 }, child_transform.GetWorldPosition());
    //and it turned too, not just moved
    try ExpectVec3Near(.{ .x = 0, .y = 1, .z = 0 }, (Vec3(f32){ .x = 1, .y = 0, .z = 0 }).QuatRotate(child_transform.GetWorldRotation()));
}

test "a child moves out with a growing parent" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const parent = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    const child = try parent.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    try child.SetTranslation(engine_context, .{ .x = 2, .y = 0, .z = 0 });
    try parent.SetTranslation(engine_context, .{ .x = 10, .y = 0, .z = 0 });

    //doubling the parent doubles the child's offset from it, as well as the child itself
    try parent.SetScale(engine_context, .{ .x = 2, .y = 2, .z = 2 });
    try PhysicsManager.UpdateWorldTransforms(.Editor, engine_context);

    const child_transform = child.GetComponent(TransformComponent).?;
    try ExpectVec3Near(.{ .x = 14, .y = 0, .z = 0 }, child_transform.GetWorldPosition());
    try ExpectVec3Near(.{ .x = 2, .y = 2, .z = 2 }, child_transform.GetWorldScale());
}

test "the transform pass and walking up the hierarchy agree" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    //three levels, each moved, turned and scaled differently, so every rule has to compose right
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const grandparent = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    const parent = try grandparent.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    const child = try parent.CreateChild(engine_context, .Entity, Entity.DefaultConfig);

    try grandparent.SetTransform(engine_context, .{ .x = 5, .y = -1, .z = 3 }, ZRotation(30), .{ .x = 2, .y = 2, .z = 2 });
    try parent.SetTransform(engine_context, .{ .x = 1, .y = 2, .z = 0 }, Quat(f32).FromAxisAngle(.{ .x = 0, .y = 1, .z = 0 }, std.math.degreesToRadians(45.0)), .{ .x = 0.5, .y = 0.5, .z = 0.5 });
    try child.SetTransform(engine_context, .{ .x = 0, .y = 0, .z = 4 }, ZRotation(-60), .{ .x = 3, .y = 3, .z = 3 });

    //the pass walks down from the root with accumulators
    try PhysicsManager.UpdateWorldTransforms(.Editor, engine_context);
    const child_transform = child.GetComponent(TransformComponent).?;
    const pass_position = child_transform.GetWorldPosition();
    const pass_rotation = child_transform.GetWorldRotation();
    const pass_scale = child_transform.GetWorldScale();

    //loading a scene instead walks up from the child through every ancestor's local transform
    child._CalculateWorldTransform();
    try ExpectVec3Near(pass_position, child_transform.GetWorldPosition());
    try ExpectVec3Near(pass_scale, child_transform.GetWorldScale());
    const probe = Vec3(f32){ .x = 1, .y = 2, .z = 3 };
    try ExpectVec3Near(probe.QuatRotate(pass_rotation), probe.QuatRotate(child_transform.GetWorldRotation()));

    //and the answer is the hand-composed one: grandparent(parent(child's offset))
    const in_grandparent = (Vec3(f32){ .x = 1, .y = 2, .z = 0 }).AddVec((Vec3(f32){ .x = 0, .y = 0, .z = 4 }).MulScalar(0.5).QuatRotate(Quat(f32).FromAxisAngle(.{ .x = 0, .y = 1, .z = 0 }, std.math.degreesToRadians(45.0))));
    const expected_world = (Vec3(f32){ .x = 5, .y = -1, .z = 3 }).AddVec(in_grandparent.MulScalar(2).QuatRotate(ZRotation(30)));
    try ExpectVec3Near(expected_world, pass_position);
}

test "a hit shape's game object is its nearest main object ancestor, or the root" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    //root -> button -> label, like a button whose label is a convenience child
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const root = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    const button = try root.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    const label = try button.CreateChild(engine_context, .Entity, Entity.DefaultConfig);

    //nothing tagged yet: every entity belongs to the root
    try std.testing.expectEqual(root.mID, label.GetMainObject().mID);
    try std.testing.expectEqual(root.mID, button.GetMainObject().mID);
    try std.testing.expectEqual(root.mID, root.GetMainObject().mID);

    //tag the button: the label now belongs to it, and the button to itself
    _ = try button.AddComponent(engine_context, MainObjectComponent{});
    try std.testing.expectEqual(button.mID, label.GetMainObject().mID);
    try std.testing.expectEqual(button.mID, button.GetMainObject().mID);
    try std.testing.expectEqual(root.mID, root.GetMainObject().mID);
}
