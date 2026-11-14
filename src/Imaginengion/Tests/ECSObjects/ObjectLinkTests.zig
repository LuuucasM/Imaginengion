//! Components that point at another object (ECSObjects/ObjectLink.zig): saved while that object isn't loaded they keep
//! it, and they link once it is, however many times it comes and goes. Script variables are in ScriptValuesTests, a bus
//! in BusSaveTests. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const TextSerializer = @import("../../Serializer/TextSerializer.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const Player = @import("../../ECSObjects/Player.zig");
const ObjectLink = @import("../../ECSObjects/ObjectLink.zig");
const UIManager = @import("../../UI/UIManager.zig");
const OverlayComponent = @import("../../ECSComponents/PComponents.zig").OverlayComponent;
const SpawnPossComponent = @import("../../ECSComponents/SComponents.zig").SpawnPossComponent;
const UIElementComponent = @import("../../ECSComponents/EComponents.zig").UIElementComponent;
const PopupRefComponent = @import("../../ECSComponents/UIComponents.zig").PopupRefComponent;

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
        engine_context._Internal.ThreadPool = std.Io.Threaded.init(engine_context._Internal.KeepHeap.allocator(), .{
            .concurrent_limit = .nothing,
            .async_limit = .nothing,
        });
        try engine_context.mUIManager.Init(engine_context);
        try engine_context.mEditorWorld.Init(engine_context);
        try engine_context.mSimulateWorld.Init(engine_context);
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        engine_context.mSimulateWorld.Deinit(engine_context);
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        engine_context.mSerializer.Deinit(engine_context.Keep());
        _ = engine_context._Internal.KeepHeap.deinit();
        self.mTmpDir.cleanup();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    fn FilePath(self: *TestWorld, file_name: []const u8) ![]const u8 {
        return std.fmt.allocPrint(self.mEngineContext.Scratch(), ".zig-cache/tmp/{s}/{s}", .{ self.mTmpDir.sub_path, file_name });
    }

    /// Whether the file at `path` has `field` saved as `uuid`
    fn Saved(self: *TestWorld, path: []const u8, field: []const u8, uuid: u64) !bool {
        const engine_context = self.mEngineContext;
        const scratch_allocator = engine_context.Scratch();
        const contents = try std.Io.Dir.cwd().readFileAlloc(engine_context.Io(), path, scratch_allocator, .unlimited);
        const line = try std.fmt.allocPrint(scratch_allocator, "\"{s}\": {d}", .{ field, uuid });
        return std.mem.indexOf(u8, contents, line) != null;
    }
};

test "a player keeps an overlay scene that isn't loaded when saved, and shows it once it is, again and again" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const editor_world = &engine_context.mEditorWorld;

    const hud = try editor_world.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    const hud_uuid = hud.GetUUID();
    const player = try editor_world.CreatePlayer(engine_context, Player.DefaultConfig);
    _ = try player.AddComponent(engine_context, OverlayComponent{ .mScene = hud });

    const player_path = try world.FilePath("player.impl");
    const hud_path = try world.FilePath("hud.imsc");
    try TextSerializer.SerializeECSObject(engine_context, player, player_path);
    try TextSerializer.SerializeECSObject(engine_context, hud, hud_path);
    editor_world.clearAndFree(engine_context, .All);

    const loaded = try editor_world.CreatePlayer(engine_context, Player.BlankConfig);
    try TextSerializer.DeserializeECSObj(engine_context, loaded, player_path);
    try std.testing.expect(loaded.GetComponent(OverlayComponent).?.GetScene() == null);

    //the small update that erased it: saved again with the scene still not loaded
    try TextSerializer.SerializeECSObject(engine_context, loaded, player_path);
    try std.testing.expect(try world.Saved(player_path, "Scene", hud_uuid));

    const first_hud = try editor_world.mSManager.CreateBlankScene(engine_context);
    try TextSerializer.DeserializeECSObj(engine_context, first_hud, hud_path);
    try std.testing.expectEqual(first_hud.mID, loaded.GetComponent(OverlayComponent).?.GetScene().?.mID);

    //closed: it waits for it and still saves it. Loaded again: it links to the new one
    try first_hud.Delete(engine_context);
    try TextSerializer.SerializeECSObject(engine_context, loaded, player_path);
    try std.testing.expect(try world.Saved(player_path, "Scene", hud_uuid));
    const second_hud = try editor_world.mSManager.CreateBlankScene(engine_context);
    try TextSerializer.DeserializeECSObj(engine_context, second_hud, hud_path);
    try std.testing.expectEqual(second_hud.mID, loaded.GetComponent(OverlayComponent).?.GetScene().?.mID);
}

test "a scene's spawn point keeps an entity that isn't loaded when saved, and links once it is" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const editor_world = &engine_context.mEditorWorld;

    const scene = try editor_world.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const spawn = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    const spawn_uuid = spawn.GetUUID();
    _ = try scene.AddComponent(engine_context, SpawnPossComponent{ .mEntityRef = spawn });

    //the entity is saved in a file of its own, so it isn't in the scene's
    const spawn_path = try world.FilePath("spawn.imen");
    try TextSerializer.SerializeECSObject(engine_context, spawn, spawn_path);
    try spawn.Delete(engine_context);
    const scene_path = try world.FilePath("level.imsc");
    try TextSerializer.SerializeECSObject(engine_context, scene, scene_path);
    try std.testing.expect(try world.Saved(scene_path, "EntityRef", spawn_uuid) == false);

    //what it wanted is lost only if it never knew: a scene read back from a file knows
    scene.GetComponentMut(SpawnPossComponent).?.mWantedUUID = spawn_uuid;
    try TextSerializer.SerializeECSObject(engine_context, scene, scene_path);
    try std.testing.expect(try world.Saved(scene_path, "EntityRef", spawn_uuid));

    const loaded = try editor_world.mSManager.CreateBlankScene(engine_context);
    try TextSerializer.DeserializeECSObj(engine_context, loaded, scene_path);
    try std.testing.expect(!loaded.GetComponent(SpawnPossComponent).?.mEntityRef.IsActive());
    try TextSerializer.SerializeECSObject(engine_context, loaded, scene_path);
    try std.testing.expect(try world.Saved(scene_path, "EntityRef", spawn_uuid));

    const loaded_spawn = try loaded.CreateEntity(engine_context, Entity.BlankConfig);
    try TextSerializer.DeserializeECSObj(engine_context, loaded_spawn, spawn_path);
    try std.testing.expectEqual(loaded_spawn.mID, loaded.GetComponent(SpawnPossComponent).?.mEntityRef.mID);
}

test "an opener keeps a popup that isn't loaded when saved, and links once it is" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const editor_world = &engine_context.mEditorWorld;

    const scene = try editor_world.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    const popup = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    const popup_uuid = popup.GetUUID();
    const opener = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try opener.AddComponent(engine_context, UIElementComponent{});
    _ = try UIManager.ElementOf(opener).?.AddComponent(engine_context, PopupRefComponent{ .mPopup = popup });

    const popup_path = try world.FilePath("popup.imen");
    const opener_path = try world.FilePath("opener.imen");
    try TextSerializer.SerializeECSObject(engine_context, popup, popup_path);
    try TextSerializer.SerializeECSObject(engine_context, opener, opener_path);
    try popup.Delete(engine_context);
    try opener.Delete(engine_context);

    const loaded = try scene.CreateEntity(engine_context, Entity.BlankConfig);
    try TextSerializer.DeserializeECSObj(engine_context, loaded, opener_path);
    try std.testing.expect(!UIManager.GetUIComponent(loaded, PopupRefComponent).?.mPopup.IsActive());
    try TextSerializer.SerializeECSObject(engine_context, loaded, opener_path);
    try std.testing.expect(try world.Saved(opener_path, "Popup", popup_uuid));

    const loaded_popup = try scene.CreateEntity(engine_context, Entity.BlankConfig);
    try TextSerializer.DeserializeECSObj(engine_context, loaded_popup, popup_path);
    try std.testing.expectEqual(loaded_popup.mID, UIManager.GetUIComponent(loaded, PopupRefComponent).?.mPopup.mID);
}

test "a waiting reference in a world Play copies links in the copy" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const editor_world = &engine_context.mEditorWorld;
    const sim_world = &engine_context.mSimulateWorld;

    const player = try editor_world.CreatePlayer(engine_context, Player.DefaultConfig);
    _ = try player.AddComponent(engine_context, OverlayComponent{ .mScene = ObjectLink.Waiting(Scene, editor_world), .mWantedUUID = 123456 });

    try editor_world.Copy(engine_context, sim_world);
    const sim_player = Player{ .mID = player.mID, .mManager = sim_world };
    try std.testing.expectEqual(sim_world, sim_player.GetComponent(OverlayComponent).?.mScene.mManager);

    const hud = try sim_world.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    try sim_world.mSManager.AddUUID(engine_context.Keep(), 123456, hud.mID);
    try sim_world.RelinkRefs(engine_context);

    try std.testing.expectEqual(hud.mID, sim_player.GetComponent(OverlayComponent).?.GetScene().?.mID);
    try std.testing.expect(player.GetComponent(OverlayComponent).?.GetScene() == null);
}

test "a reference wants what it points at, nothing when empty, and what it wanted when waiting" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const editor_world = &engine_context.mEditorWorld;

    const scene = try editor_world.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const dropped = try scene.CreateEntity(engine_context, Entity.DefaultConfig);

    try std.testing.expectEqual(@as(?u64, dropped.GetUUID()), ObjectLink.WantedNow(dropped, 123456));
    try std.testing.expectEqual(@as(?u64, null), ObjectLink.WantedNow(Entity.uninit, 123456));
    try std.testing.expectEqual(@as(?u64, 123456), ObjectLink.WantedNow(ObjectLink.Waiting(Entity, editor_world), 123456));
}
