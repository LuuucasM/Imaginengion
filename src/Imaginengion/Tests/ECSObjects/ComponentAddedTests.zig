//! What adding a component sets off (Manager.OnComponentAdded) runs as soon as the component is added, also when its
//! type is locked (ECSManager.Lock) and the component only staged until the end of the frame: the side effects read
//! and write the staged copy, and what they wrote is what lands. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const ECSEventData = @import("../../Events/ECSEventData.zig");

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const TransformComponent = EntityComponents.TransformComponent;
const TransformDirtyTag = EntityComponents.TransformDirtyTag;
const RigidBodyComponent = EntityComponents.RigidBodyComponent;
const StaticBodyTag = EntityComponents.StaticBodyTag;
const DynamicBodyTag = EntityComponents.DynamicBodyTag;

const TestWorld = struct {
    mEngineContext: *EngineContext,

    fn Init() !*TestWorld {
        const self = try std.heap.page_allocator.create(TestWorld);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        self.mEngineContext.* = .{};
        try self.mEngineContext.mEditorWorld.Init(self.mEngineContext);
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        engine_context.mEditorWorld.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    fn NewBlankEntity(self: *TestWorld) !Entity {
        const engine_context = self.mEngineContext;
        const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
        return try scene.CreateEntity(engine_context, Entity.BlankConfig);
    }

    /// How many entities have `component_type` in the entity ECS's arrays, which is what queries see
    fn NumInArrays(self: *TestWorld, comptime component_type: type) usize {
        return self.mEngineContext.mEditorWorld.mEManager.mECSManager.NumWithComponent(component_type);
    }

    /// Locks these entity components, so their adds are staged until Unlock
    fn Lock(self: *TestWorld, comptime locked_types: []const type) void {
        self.mEngineContext.mEditorWorld.mEManager.mECSManager.Lock(locked_types);
    }

    fn Unlock(self: *TestWorld, comptime locked_types: []const type) !void {
        try self.mEngineContext.mEditorWorld.mEManager.mECSManager.Unlock(self.mEngineContext, locked_types);
    }

    /// The world's ECS events at the end of the frame, listeners included
    fn EndOfFrame(self: *TestWorld) !void {
        var callback_list: std.DoublyLinkedList = .{};
        try self.mEngineContext.mEditorWorld.ProcessEvents(ECSEventData, .EndOfFrame, self.mEngineContext, &callback_list);
    }
};

test "a transform is tagged dirty as soon as it is added" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const entity = try world.NewBlankEntity();
    const transforms_before = world.NumInArrays(TransformComponent);
    world.Lock(&.{TransformComponent});
    _ = try entity.AddComponent(engine_context, TransformComponent{});

    //the tag is on now, while the transform itself is only staged
    try std.testing.expect(entity.HasComponent(TransformDirtyTag));
    try std.testing.expect(entity.HasComponent(TransformComponent));
    try std.testing.expectEqual(transforms_before, world.NumInArrays(TransformComponent));

    try world.Unlock(&.{TransformComponent});

    try std.testing.expectEqual(transforms_before + 1, world.NumInArrays(TransformComponent));
    try std.testing.expect(entity.HasComponent(TransformDirtyTag));
}

test "a rigid body gets its type tag and mass as soon as it is added, and lands with them" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const entity = try world.NewBlankEntity();
    //below the minimum, which syncing the body brings back up
    world.Lock(&.{RigidBodyComponent});
    const staged_body = try entity.AddComponent(engine_context, RigidBodyComponent{ ._Mass = 0 });

    //synced through the staged copy
    try std.testing.expect(entity.HasComponent(DynamicBodyTag));
    try std.testing.expectEqual(RigidBodyComponent.MIN_MASS, staged_body._Mass);
    try std.testing.expectEqual(staged_body, entity.GetComponent(RigidBodyComponent).?);

    try world.Unlock(&.{RigidBodyComponent});

    const rigid_body = entity.GetComponent(RigidBodyComponent).?;
    try std.testing.expect(rigid_body != staged_body);
    try std.testing.expectEqual(RigidBodyComponent.MIN_MASS, rigid_body._Mass);
    try std.testing.expectEqual(1.0 / RigidBodyComponent.MIN_MASS, rigid_body._InvMass);
}

test "a body type tag replaces the type a staged body had" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const entity = try world.NewBlankEntity();
    world.Lock(&.{RigidBodyComponent});
    _ = try entity.AddComponent(engine_context, RigidBodyComponent{});
    try world.Unlock(&.{RigidBodyComponent});
    try std.testing.expect(entity.HasComponent(DynamicBodyTag));

    //the body is still staged, and the tag swap reaches it all the same
    _ = try entity.AddComponent(engine_context, StaticBodyTag{});
    try std.testing.expect(entity.HasComponent(StaticBodyTag));
    try std.testing.expect(!entity.HasComponent(DynamicBodyTag));
    try std.testing.expectEqual(@as(f32, 0), entity.GetComponent(RigidBodyComponent).?._InvMass);

    try world.EndOfFrame();

    try std.testing.expect(entity.HasComponent(StaticBodyTag));
    try std.testing.expect(!entity.HasComponent(DynamicBodyTag));
    try std.testing.expectEqual(@as(f32, 0), entity.GetComponent(RigidBodyComponent).?._InvMass);
}

test "a staged add for an entity deleted the same frame goes with it" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const entity = try world.NewBlankEntity();
    world.Lock(&.{ RigidBodyComponent, TransformComponent });
    _ = try entity.AddComponent(engine_context, RigidBodyComponent{});
    try engine_context.mEditorWorld.mEManager.mECSManager.DestroyEntity(engine_context, entity.mID);
    _ = try entity.AddComponent(engine_context, TransformComponent{});
    try world.Unlock(&.{ RigidBodyComponent, TransformComponent });

    try world.EndOfFrame();

    try std.testing.expect(!entity.IsActive());
}
