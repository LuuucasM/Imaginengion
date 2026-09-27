//! A player's overlays: the OverlayComponents on it and its child players, each showing one overlay scene in
//! that player's view. No window or renderer needed. Run with `zig build test-engine`.
//! A spawned copy of a player template dropping its overlay is in TmplTests.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const TextSerializer = @import("../../Serializer/TextSerializer.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const Player = @import("../../ECSObjects/Player.zig");

const PlayerComponents = @import("../../ECSComponents/PComponents.zig");
const OverlayComponent = PlayerComponents.OverlayComponent;
const NameComponent = PlayerComponents.NameComponent;

const SEventData = @import("../../Events/SManagerData.zig");
const PEventData = @import("../../Events/PManagerData.zig");
const EEventData = @import("../../Events/EManagerData.zig");
const ECSEventData = @import("../../Events/ECSEventData.zig");

const TestWorld = struct {
    mEngineContext: *EngineContext,
    mTmpDir: std.testing.TmpDir,

    fn Init() !*TestWorld {
        const self = try std.heap.page_allocator.create(TestWorld);
        self.* = .{
            .mEngineContext = try std.heap.page_allocator.create(EngineContext),
            .mTmpDir = std.testing.tmpDir(.{}),
        };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        //UUIDs and file reads/writes go through the context's Io, which forwards to this
        engine_context._Internal.ThreadedIO = std.Io.Threaded.init(engine_context._Internal.EngineGPA.allocator(), .{
            .concurrent_limit = .nothing,
            .async_limit = .nothing,
        });
        try engine_context.mEditorWorld.Init(engine_context.EngineAllocator());
        //play mode's copy of the world
        try engine_context.mSimulateWorld.Init(engine_context.EngineAllocator());
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mSimulateWorld.Deinit(engine_context);
        //loading an overlay reference queues a UUID resolve in here
        engine_context.mSerializer.Deinit(engine_context.EngineAllocator());
        _ = engine_context._Internal.EngineGPA.deinit();
        self.mTmpDir.cleanup();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    /// A path in this test's temporary folder, relative to the working directory like the serializer expects
    fn FilePath(self: *TestWorld, file_name: []const u8) ![]const u8 {
        return std.fmt.allocPrint(self.mEngineContext.FrameAllocator(), ".zig-cache/tmp/{s}/{s}", .{ self.mTmpDir.sub_path, file_name });
    }

    /// EditorProgram.OnUpdate's end of frame for the editor world, where deletes happen
    fn EndFrame(self: *TestWorld) !void {
        const engine_context = self.mEngineContext;
        const world = &engine_context.mEditorWorld;
        var callback_list: std.DoublyLinkedList = .{};
        try world.ProcessEvents(SEventData, .EndOfFrame, engine_context, &callback_list);
        try world.ProcessEvents(PEventData, .EndOfFrame, engine_context, &callback_list);
        try world.ProcessEvents(EEventData, .EndOfFrame, engine_context, &callback_list);
        try world.ProcessEvents(ECSEventData, .EndOfFrame, engine_context, &callback_list);
    }
};

fn NewPlayer(engine_context: *EngineContext) !Player {
    return try engine_context.mEditorWorld.CreatePlayer(engine_context, Player.DefaultConfig);
}

fn NewScene(engine_context: *EngineContext, layer: Scene.LayerType, name: []const u8) !Scene {
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, layer, Scene.DefaultConfig);
    const name_list = &scene.GetComponent(NameComponent).?.mName;
    name_list.clearRetainingCapacity();
    try name_list.appendSlice(engine_context.EngineAllocator(), name);
    return scene;
}

test "AddOverlay shows an overlay scene through a new child player named after it" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const player = try NewPlayer(engine_context);
    const hud = try NewScene(engine_context, .OverlayLayer, "HUD");

    const child = try player.AddOverlay(engine_context, hud);

    try std.testing.expectEqualStrings("HUD", child.GetName());
    try std.testing.expectEqual(hud.mID, child.GetComponent(OverlayComponent).?.GetScene().?.mID);
    //the overlay is on the child, the player itself is left as it was
    try std.testing.expect(!player.HasComponent(OverlayComponent));
    var child_iter = player.GetIterator(.Child);
    try std.testing.expectEqual(child.mID, child_iter.next().?.mID);
    try std.testing.expect(child_iter.next() == null);
}

test "only an overlay scene can be added as an overlay" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const player = try NewPlayer(engine_context);
    const level = try NewScene(engine_context, .GameLayer, "Level");

    try std.testing.expectError(error.NotAnOverlayScene, player.AddOverlay(engine_context, level));
    try std.testing.expectError(error.InvalidScene, player.AddOverlay(engine_context, Scene.uninit));
    //and nothing was left behind by the tries
    var child_iter = player.GetIterator(.Child);
    try std.testing.expect(child_iter.next() == null);
}

test "an overlay whose scene is gone, or was never set, has no scene" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const player = try NewPlayer(engine_context);
    const hud = try NewScene(engine_context, .OverlayLayer, "HUD");
    const child = try player.AddOverlay(engine_context, hud);

    try std.testing.expect((OverlayComponent{}).GetScene() == null);

    try hud.Delete(engine_context);
    try world.EndFrame();
    try std.testing.expect(child.GetComponent(OverlayComponent).?.GetScene() == null);
}

test "an overlay reference round trips, even when the player is loaded before its scene" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const hud = try NewScene(engine_context, .OverlayLayer, "HUD");
    const hud_uuid = hud.GetUUID();
    const player = try NewPlayer(engine_context);
    _ = try player.AddComponent(engine_context, OverlayComponent{ .mScene = hud });

    const player_path = try world.FilePath("player_one.impl");
    const scene_path = try world.FilePath("hud.imsc");
    try TextSerializer.SerializeECSObject(engine_context, player, player_path);
    try TextSerializer.SerializeECSObject(engine_context, hud, scene_path);
    engine_context.mEditorWorld.clearAndFree(engine_context, .All);

    //the scene it points at isn't loaded yet, so the reference waits
    const loaded_player = try engine_context.mEditorWorld.CreatePlayer(engine_context, Player.BlankConfig);
    try TextSerializer.DeserializeECSObj(engine_context, loaded_player, player_path);
    engine_context.mSerializer.ResolveUUIDs();
    try std.testing.expect(loaded_player.GetComponent(OverlayComponent).?.GetScene() == null);

    //and is filled in once it is
    const loaded_hud = try engine_context.mEditorWorld.mSManager.CreateBlankScene(engine_context);
    try TextSerializer.DeserializeECSObj(engine_context, loaded_hud, scene_path);
    engine_context.mSerializer.ResolveUUIDs();
    const scene = loaded_player.GetComponent(OverlayComponent).?.GetScene().?;
    try std.testing.expectEqual(loaded_hud.mID, scene.mID);
    try std.testing.expectEqual(hud_uuid, scene.GetUUID());
}

test "a copied world's overlays point at the copy's scenes" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const player = try NewPlayer(engine_context);
    const hud = try NewScene(engine_context, .OverlayLayer, "HUD");
    const child = try player.AddOverlay(engine_context, hud);

    //what pressing play does
    try engine_context.mEditorWorld.Copy(engine_context, &engine_context.mSimulateWorld);

    const copied_child = engine_context.mSimulateWorld.GetPlayer(child.mID);
    const copied_scene = copied_child.GetComponent(OverlayComponent).?.GetScene().?;
    try std.testing.expectEqual(hud.mID, copied_scene.mID);
    try std.testing.expectEqual(&engine_context.mSimulateWorld, copied_scene.mManager);
}

fn ExpectScenes(player: Player, frame_allocator: std.mem.Allocator, expected: []const Scene) !void {
    const scenes = try player.GetOverlayScenes(frame_allocator);
    try std.testing.expectEqual(expected.len, scenes.items.len);
    for (expected) |scene| {
        try std.testing.expect(std.mem.indexOfScalar(Scene.Type, scenes.items, scene.mID) != null);
    }
}

test "a player with no overlays sees none" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const player = try NewPlayer(engine_context);
    //an overlay scene existing isn't enough, the player has to be shown it
    _ = try NewScene(engine_context, .OverlayLayer, "HUD");
    _ = try player.CreateChild(engine_context, .Entity, Player.DefaultConfig);

    try ExpectScenes(player, engine_context.FrameAllocator(), &.{});
}

test "a player sees the overlays on itself and everywhere below it" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const frame_allocator = engine_context.FrameAllocator();

    const player = try NewPlayer(engine_context);
    const hud = try NewScene(engine_context, .OverlayLayer, "HUD");
    const pause = try NewScene(engine_context, .OverlayLayer, "Pause");
    const cockpit = try NewScene(engine_context, .OverlayLayer, "Cockpit");
    const radar = try NewScene(engine_context, .OverlayLayer, "Radar");

    _ = try player.AddComponent(engine_context, OverlayComponent{ .mScene = hud });
    _ = try player.AddOverlay(engine_context, pause);
    //a child grouping the plane's UI, one of them another level down
    const plane_ui = try player.AddOverlay(engine_context, cockpit);
    _ = try plane_ui.AddOverlay(engine_context, radar);

    try ExpectScenes(player, frame_allocator, &.{ hud, pause, cockpit, radar });
    //the plane's group on its own only sees what's under it
    try ExpectScenes(plane_ui, frame_allocator, &.{ cockpit, radar });
}

test "a scene shown twice is listed once, and a deleted one is left out" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const frame_allocator = engine_context.FrameAllocator();

    const player = try NewPlayer(engine_context);
    const hud = try NewScene(engine_context, .OverlayLayer, "HUD");
    const pause = try NewScene(engine_context, .OverlayLayer, "Pause");
    _ = try player.AddOverlay(engine_context, hud);
    _ = try player.AddOverlay(engine_context, hud);
    _ = try player.AddOverlay(engine_context, pause);

    try ExpectScenes(player, frame_allocator, &.{ hud, pause });

    try pause.Delete(engine_context);
    try world.EndFrame();
    try ExpectScenes(player, frame_allocator, &.{hud});
}

test "a game layer scene put straight into an overlay component is not seen" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const player = try NewPlayer(engine_context);
    const level = try NewScene(engine_context, .GameLayer, "Level");
    //AddOverlay and the editor refuse this, but the field can still be written
    _ = try player.AddComponent(engine_context, OverlayComponent{ .mScene = level });

    try ExpectScenes(player, engine_context.FrameAllocator(), &.{});
}
