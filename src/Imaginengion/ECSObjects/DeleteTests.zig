//! Object.Delete for every object type: it only queues, the end of frame ProcessEvents calls apply it, and
//! it takes children, a scene's entities and UUID map entries along. No window or renderer needed.
//! Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("Entity.zig");
const Scene = @import("Scene.zig");
const Player = @import("Player.zig");
const GameContext = @import("GameContext.zig");

const StackPosComponent = @import("../ECSComponents/SComponents.zig").StackPosComponent;
const UUIDComponent = @import("../ECSComponents/Shared/UUIDComponent.zig");
const NameComponent = @import("../ECSComponents/Shared/NameComponent.zig");
const ECSObject = @import("ECSObject.zig");

const EEventData = @import("../Events/EManagerData.zig");
const GCEventData = @import("../Events/GCManagerData.zig");
const PEventData = @import("../Events/PManagerData.zig");
const SEventData = @import("../Events/SManagerData.zig");
const ECSEventData = @import("../Events/ECSEventData.zig");

const TestWorld = struct {
    mEngineContext: *EngineContext,

    fn Init() !*TestWorld {
        const self = try std.heap.page_allocator.create(TestWorld);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        //UUIDs are drawn from the context's Io, which forwards to this
        engine_context._Internal.ThreadedIO = std.Io.Threaded.init(engine_context._Internal.EngineGPA.allocator(), .{
            .concurrent_limit = .nothing,
            .async_limit = .nothing,
        });
        try engine_context.mEditorWorld.Init(engine_context.EngineAllocator());
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        engine_context.mEditorWorld.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    /// The same end of frame order as EditorProgram.OnUpdate
    fn EndFrame(self: *TestWorld) !void {
        const engine_context = self.mEngineContext;
        const world = &engine_context.mEditorWorld;
        var callback_list: std.DoublyLinkedList = .{};
        try world.ProcessEvents(SEventData, .EndOfFrame, engine_context, &callback_list);
        try world.ProcessEvents(GCEventData, .EndOfFrame, engine_context, &callback_list);
        try world.ProcessEvents(PEventData, .EndOfFrame, engine_context, &callback_list);
        try world.ProcessEvents(EEventData, .EndOfFrame, engine_context, &callback_list);
        try world.ProcessEvents(ECSEventData, .EndOfFrame, engine_context, &callback_list);
    }

    fn EntityByUUID(self: *TestWorld, uuid: u64) ?Entity {
        return self.mEngineContext.mEditorWorld.GetObjectByUUID(Entity, uuid);
    }
};

test "deleting an entity takes its children and their UUIDs along at the end of the frame" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const root = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    const child = try root.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    const grandchild = try child.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    const sibling = try scene.CreateEntity(engine_context, Entity.DefaultConfig);

    const root_uuid = root.GetUUID();
    const child_uuid = child.GetUUID();
    const grandchild_uuid = grandchild.GetUUID();

    try root.Delete(engine_context);

    //still usable for the rest of the frame
    try std.testing.expect(root.IsActive());
    try std.testing.expect(grandchild.IsActive());
    try std.testing.expect(world.EntityByUUID(root_uuid) != null);

    try world.EndFrame();

    try std.testing.expect(!root.IsActive());
    try std.testing.expect(!child.IsActive());
    try std.testing.expect(!grandchild.IsActive());
    try std.testing.expect(world.EntityByUUID(root_uuid) == null);
    try std.testing.expect(world.EntityByUUID(child_uuid) == null);
    try std.testing.expect(world.EntityByUUID(grandchild_uuid) == null);

    //nothing else in the scene went with it
    try std.testing.expect(sibling.IsActive());
    try std.testing.expect(scene.IsActive());
    try std.testing.expectEqual(sibling.mID, world.EntityByUUID(sibling.GetUUID()).?.mID);
}

test "deleting twice in a frame, or deleting something already gone, does nothing" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const entity = try scene.CreateEntity(engine_context, Entity.DefaultConfig);

    try entity.Delete(engine_context);
    try entity.Delete(engine_context);
    try std.testing.expectEqual(@as(usize, 1), engine_context.mEditorWorld.mEManager.mEventManager.mEventsArray.getPtr(.EndOfFrame).items.len);

    try world.EndFrame();
    try std.testing.expect(!entity.IsActive());

    try entity.Delete(engine_context);
    try std.testing.expectEqual(@as(usize, 0), engine_context.mEditorWorld.mEManager.mEventManager.mEventsArray.getPtr(.EndOfFrame).items.len);
    try world.EndFrame();
}

test "deleting a duplicate leaves its original's UUID entry alone" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const original = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    const copy = try original.Duplicate(engine_context);
    try std.testing.expectEqual(original.GetUUID(), copy.GetUUID());

    try copy.Delete(engine_context);
    try world.EndFrame();

    try std.testing.expect(!copy.IsActive());
    try std.testing.expectEqual(original.mID, world.EntityByUUID(original.GetUUID()).?.mID);
}

test "deleting a scene takes its entities along and closes the gap in the scene stack" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene_manager = &engine_context.mEditorWorld.mSManager;

    const game_a = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const game_b = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const overlay = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);

    const a_root = try game_a.CreateEntity(engine_context, Entity.DefaultConfig);
    const a_child = try a_root.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    const a_other = try game_a.CreateEntity(engine_context, Entity.DefaultConfig);
    const b_entity = try game_b.CreateEntity(engine_context, Entity.DefaultConfig);

    const a_uuid = game_a.GetUUID();
    const a_child_uuid = a_child.GetUUID();

    //deleting one of its entities as well in the same frame must not trip anything up
    try a_other.Delete(engine_context);
    try game_a.Delete(engine_context);
    try world.EndFrame();

    try std.testing.expect(!game_a.IsActive());
    try std.testing.expect(!a_root.IsActive());
    try std.testing.expect(!a_child.IsActive());
    try std.testing.expect(!a_other.IsActive());
    try std.testing.expect(engine_context.mEditorWorld.GetObjectByUUID(Scene, a_uuid) == null);
    try std.testing.expect(world.EntityByUUID(a_child_uuid) == null);

    try std.testing.expect(game_b.IsActive());
    try std.testing.expect(overlay.IsActive());
    try std.testing.expect(b_entity.IsActive());

    //two layers left, the one game layer below the overlay
    try std.testing.expectEqual(@as(usize, 2), scene_manager.mNumofLayers);
    try std.testing.expectEqual(@as(usize, 1), scene_manager.mGameLayerInsertIndex);
    try std.testing.expectEqual(@as(usize, 0), game_b.GetComponent(StackPosComponent).?.mPosition);
    try std.testing.expectEqual(@as(usize, 1), overlay.GetComponent(StackPosComponent).?.mPosition);

    //a new game layer still lands between them
    const game_c = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    try std.testing.expectEqual(@as(usize, 1), game_c.GetComponent(StackPosComponent).?.mPosition);
    try std.testing.expectEqual(@as(usize, 2), overlay.GetComponent(StackPosComponent).?.mPosition);
}

test "deleting a scene twice in a frame only closes the gap once" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const game_a = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const game_b = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    try game_a.Delete(engine_context);
    try game_a.Delete(engine_context);
    try world.EndFrame();

    try std.testing.expectEqual(@as(usize, 1), engine_context.mEditorWorld.mSManager.mNumofLayers);
    try std.testing.expectEqual(@as(usize, 0), game_b.GetComponent(StackPosComponent).?.mPosition);
}

test "players and game contexts delete the same way" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const player = try engine_context.mEditorWorld.CreatePlayer(engine_context, Player.DefaultConfig);
    const game_context = try engine_context.mEditorWorld.CreateGameContext(engine_context, GameContext.DefaultConfig);
    const player_uuid = player.GetUUID();
    const game_context_uuid = game_context.GetUUID();

    try player.Delete(engine_context);
    try game_context.Delete(engine_context);
    try std.testing.expect(player.IsActive());
    try std.testing.expect(game_context.IsActive());

    try world.EndFrame();

    try std.testing.expect(!player.IsActive());
    try std.testing.expect(!game_context.IsActive());
    try std.testing.expect(engine_context.mEditorWorld.GetObjectByUUID(Player, player_uuid) == null);
    try std.testing.expect(engine_context.mEditorWorld.GetObjectByUUID(GameContext, game_context_uuid) == null);
}

test "script children have a name but no UUID, and go along with their object, for every object type" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const editor_world = &engine_context.mEditorWorld;

    const scene = try editor_world.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const objects = .{
        try scene.CreateEntity(engine_context, Entity.DefaultConfig),
        try editor_world.NewScene(engine_context, .GameLayer, Scene.DefaultConfig),
        try editor_world.CreatePlayer(engine_context, Player.DefaultConfig),
        try editor_world.CreateGameContext(engine_context, GameContext.DefaultConfig),
    };

    inline for (objects) |object| {
        const obj_t = @TypeOf(object);
        //Core's AddScript directly: the per type wrappers load the script to read its type, which needs a built script
        const script = try ECSObject.Core(obj_t).AddScript(object, engine_context, .uninit);
        try std.testing.expect(!script.HasComponent(UUIDComponent));
        try std.testing.expect(script.HasComponent(NameComponent));

        try object.Delete(engine_context);
        try world.EndFrame();
        try std.testing.expect(!script.IsActive());
    }
}
