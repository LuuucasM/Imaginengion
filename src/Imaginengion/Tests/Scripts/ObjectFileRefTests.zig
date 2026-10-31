//! File ref script variables (Scripts/ObjectFileRef.zig, IM.SceneRef and the others): Get loading the file once, Spawn
//! making copies, being saved by path and UUID and read back, the reference on the file following the variable through
//! every copy and new build, and the editor's rows taking dropped files and hierarchy rows. Files are real, saved to a
//! temporary folder as TmplTests does; scripts are exported in-process as ScriptValuesTests does. No window or renderer
//! needed. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const WorldManager = @import("../../Core/WorldManager.zig");
const TextSerializer = @import("../../Serializer/TextSerializer.zig");
const AssetHandle = @import("../../ECSObjects/AssetHandle.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const Player = @import("../../ECSObjects/Player.zig");
const GameContext = @import("../../ECSObjects/GameContext.zig");
const ECSObject = @import("../../ECSObjects/ECSObject.zig");
const Assets = @import("../../ECSComponents/AComponents.zig");
const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const ScriptComponent = EntityComponents.ScriptComponent;
const UUIDComponent = EntityComponents.UUIDComponent;
const ObjectRefComponent = EntityComponents.ObjectRefComponent;
const FileRefComponent = EntityComponents.FileRefComponent;
const DropTargetComponent = EntityComponents.DropTargetComponent;
const TextComponent = EntityComponents.TextComponent;
const PointerSystem = @import("../../Pointer/PointerSystem.zig");
const ScriptABI = @import("../../Scripts/ScriptABI.zig");
const ScriptExport = @import("../../Scripts/ScriptExport.zig");
const ScriptValues = @import("../../Scripts/ScriptValues.zig");
const ObjectFileRef = @import("../../Scripts/ObjectFileRef.zig").ObjectFileRef;
const UIManager = @import("../../UI/UIManager.zig");
const BindingSystem = @import("../../UI/BindingSystem.zig");
const WidgetActions = @import("../../UI/WidgetActions.zig");

const EEventData = @import("../../Events/EManagerData.zig");
const GCEventData = @import("../../Events/GCManagerData.zig");
const PEventData = @import("../../Events/PManagerData.zig");
const SEventData = @import("../../Events/SManagerData.zig");
const ECSEventData = @import("../../Events/ECSEventData.zig");

const EntityRef = ObjectFileRef(Entity);
const SceneRef = ObjectFileRef(Scene);
const PlayerRef = ObjectFileRef(Player);
const GameContextRef = ObjectFileRef(GameContext);

const NO_SCRIPTS = @import("../../UI/Widgets.zig").Options{ .StockScripts = false };

/// A script with a file ref of each type
const Menu = struct {
    mEntity: EntityRef = .uninit,
    mScene: SceneRef = .uninit,
    mPlayer: PlayerRef = .uninit,
    mGameContext: GameContextRef = .uninit,

    pub fn OnUpdate(_: *Menu, _: *EngineContext, _: Entity) ScriptABI.ScriptResult {
        return .Continue;
    }
};
const MenuExports = ScriptExport.Exports(Menu, "Menu", &.{});

/// Menu after an edit: mScene kept, mPlayer now another kind, the others gone
const MenuEdited = struct {
    mScene: SceneRef = .uninit,
    mPlayer: f32 = 0.5,

    pub fn OnUpdate(_: *MenuEdited, _: *EngineContext, _: Entity) ScriptABI.ScriptResult {
        return .Continue;
    }
};
const MenuEditedExports = ScriptExport.Exports(MenuEdited, "MenuEdited", &.{});

const TestWorld = struct {
    mEngineContext: *EngineContext,
    mTmpDir: std.testing.TmpDir,
    /// where what is loaded and scripts go
    mLevel: Scene = undefined,
    /// where what is saved to a file and the editor's rows go, so a load never finds the original
    mSource: Scene = undefined,
    mUIScene: Scene = undefined,

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
        //no Setup: its default assets need the GPU
        try engine_context.mAssetManager.Init(engine_context);
        try engine_context.mAssetWorld.Init(engine_context);
        engine_context.mAssetEntityScene = try engine_context.mAssetWorld.NewScene(engine_context, .GameLayer, Scene.BlankConfig);
        try engine_context.mUIManager.Init(engine_context);
        try engine_context.mGameWorld.Init(engine_context);
        try engine_context.mSimulateWorld.Init(engine_context);
        try engine_context.mEditorWorld.Init(engine_context);
        self.mLevel = try engine_context.mGameWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
        self.mSource = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
        self.mUIScene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        const engine_allocator = engine_context.EngineAllocator();
        //everything that holds asset handles goes while the asset manager is still alive, as in EngineContext.DeInit
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mSimulateWorld.Deinit(engine_context);
        engine_context.mGameWorld.Deinit(engine_context);
        engine_context.mAssetWorld.clearAndFree(engine_context, .All);
        engine_context.mSerializer.Deinit(engine_allocator);
        const asset_manager = &engine_context.mAssetManager;
        asset_manager.mECSManager.Deinit(engine_context);
        asset_manager.mUUIDToWorldID.deinit(engine_allocator);
        asset_manager.mEventManager.Deinit(engine_allocator);
        asset_manager.mCWDPath.deinit(engine_allocator);
        engine_context.mAssetWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);

        _ = engine_context._Internal.EngineGPA.deinit();
        self.mTmpDir.cleanup();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    fn GameWorld(self: *TestWorld) *WorldManager {
        return &self.mEngineContext.mGameWorld;
    }

    fn SourceWorld(self: *TestWorld) *WorldManager {
        return &self.mEngineContext.mEditorWorld;
    }

    /// A path in this test's temporary folder, relative to the working directory like an engine asset path
    fn TmpPath(self: *TestWorld, file_name: []const u8) ![]const u8 {
        return std.fmt.allocPrint(self.mEngineContext.FrameAllocator(), ".zig-cache/tmp/{s}/{s}", .{ self.mTmpDir.sub_path, file_name });
    }

    /// Saves `object` to a file and returns a handle to it, which is the caller's reference
    fn SaveFile(self: *TestWorld, object: anytype, file_name: []const u8) !AssetHandle {
        const engine_context = self.mEngineContext;
        const rel_path = try self.TmpPath(file_name);
        try TextSerializer.SerializeECSObject(engine_context, object, rel_path);
        return try engine_context.mAssetManager.GetAssetHandle(engine_context, .{ .File = .{ .rel_path = rel_path, .path_type = .Eng } });
    }

    fn Refs(self: *TestWorld, handle: AssetHandle) usize {
        return self.mEngineContext.mAssetManager.mECSManager.GetComponent(Assets.AssetMetaData, handle.mID).?.mRefs;
    }

    /// A loaded script asset running `info`, as if its DLL had handed it over. The handle is the caller's reference
    fn ScriptAssetFor(self: *TestWorld, info: *const ScriptABI.ScriptInfo) !AssetHandle {
        const engine_context = self.mEngineContext;
        const asset_manager = &engine_context.mAssetManager;
        const engine_allocator = engine_context.EngineAllocator();
        const asset_id = try asset_manager.mECSManager.CreateEntity(engine_allocator);
        _ = try asset_manager.mECSManager.AddComponentSync(engine_context, asset_id, Assets.AssetMetaData{ .mRefs = 1 });
        var file_meta_data = Assets.FileMetaData{ .mPathType = .Prj };
        _ = try file_meta_data.mRelPath.print(engine_allocator, "scripts/Menu.zig", .{});
        _ = try asset_manager.mECSManager.AddComponentSync(engine_context, asset_id, file_meta_data);
        _ = try asset_manager.mECSManager.AddComponentSync(engine_context, asset_id, Assets.ScriptAsset{ ._Info = info });
        return .{ .mID = asset_id, .mManager = asset_manager };
    }

    /// An entity in the level with a script running `handle` (which keeps a reference of its own), and the script child
    fn EntityWithScript(self: *TestWorld, handle: AssetHandle) !struct { Entity, Entity } {
        const engine_context = self.mEngineContext;
        const entity = try self.mLevel.CreateEntity(engine_context, Entity.DefaultConfig);
        handle.RetainAsset();
        const script = try ECSObject.Core(Entity).AddScript(entity, engine_context, handle);
        return .{ entity, script };
    }

    /// EditorProgram.OnUpdate's end of frame for one world
    fn EndFrame(self: *TestWorld, world: *WorldManager) !void {
        const engine_context = self.mEngineContext;
        var callback_list: std.DoublyLinkedList = .{};
        try world.ProcessEvents(SEventData, .EndOfFrame, engine_context, &callback_list);
        try world.ProcessEvents(GCEventData, .EndOfFrame, engine_context, &callback_list);
        try world.ProcessEvents(PEventData, .EndOfFrame, engine_context, &callback_list);
        try world.ProcessEvents(EEventData, .EndOfFrame, engine_context, &callback_list);
        try world.ProcessEvents(ECSEventData, .EndOfFrame, engine_context, &callback_list);
    }

    /// `source` let go over `target`: the pointer system only drops on a target what it takes
    fn Drop(self: *TestWorld, source: Entity, target: Entity) !void {
        if (!PointerSystem.Takes(target.GetComponent(DropTargetComponent).?.*, source)) return;
        try self.mEngineContext.mUIManager.OnPointerEvent(self.mEngineContext, .{ .mEntity = target, .mEvent = .{ .PointerDropped = .{ .mSource = source, .mPosition = .{ .x = 0, .y = 0, .z = 0 } } } });
    }

    /// A left click on the Clear item of `box`'s right-click menu
    fn Clear(self: *TestWorld, box: Entity) !void {
        var items = WidgetActions.PopupOf(box).?.GetIterator(.Child);
        const clear = items.next().?;
        try self.mEngineContext.mUIManager.OnPointerEvent(self.mEngineContext, .{ .mEntity = clear, .mEvent = .{ .PointerClicked = .{ .mButton = .BUTTON_LEFT, .mClicks = 1, .mPosition = .{ .x = 0, .y = 0, .z = 0 }, .mTarget = clear } } });
    }

    /// Something being dragged carrying a file, the way a Content Browser tile does
    fn FileTile(self: *TestWorld, rel_path: []const u8) !Entity {
        const engine_context = self.mEngineContext;
        const tile = try self.mUIScene.CreateEntity(engine_context, Entity.DefaultConfig);
        _ = try tile.AddComponent(engine_context, try FileRefComponent.Init(engine_context, rel_path, .Eng));
        return tile;
    }

    /// Something being dragged carrying `object`, the way a hierarchy row does
    fn ObjectRow(self: *TestWorld, object: anytype) !Entity {
        const row = try self.mUIScene.CreateEntity(self.mEngineContext, Entity.DefaultConfig);
        _ = try row.AddComponent(self.mEngineContext, ObjectRefComponent{ .mObject = .Of(object) });
        return row;
    }

    fn ShowFields(self: *TestWorld) !void {
        try self.mEngineContext.mSystems.RunSystem(BindingSystem.Update, self.mEngineContext, .{&self.mEngineContext.mUIManager.mBindingSystem});
    }
};

fn MenuOf(script: Entity) *Menu {
    const instance = ScriptValues.InstanceOf(script.GetComponent(ScriptComponent).?).?;
    return @ptrCast(@alignCast(instance.mData));
}

fn FirstScript(object: Entity) Entity {
    var scripts = object.GetIterator(.Script);
    return scripts.next().?;
}

/// Get loading the file `object` was saved to once, and again once what it loaded is gone, and Spawn making copies
fn CheckGetAndSpawn(world: *TestWorld, comptime Ref: type, object: Ref.Object, file_name: []const u8, where: Ref.Where) !void {
    const engine_context = world.mEngineContext;
    var ref: Ref = .{ .mFile = try world.SaveFile(object, file_name) };
    defer ref.Release();

    const first = try ref.Get(engine_context, where);
    try std.testing.expect(first.mManager == world.GameWorld());
    try std.testing.expectEqual(object.GetUUID(), first.GetUUID());
    try std.testing.expectEqual(first.mID, ref.mObject.mID);
    try std.testing.expectEqual(first.mID, (try ref.Get(engine_context, where)).mID);

    const a = try ref.Spawn(engine_context, where);
    const b = try ref.Spawn(engine_context, where);
    try std.testing.expect(a.mID != first.mID and b.mID != first.mID and a.mID != b.mID);
    try std.testing.expect(!a.HasComponent(UUIDComponent) and !b.HasComponent(UUIDComponent));
    try std.testing.expectEqual(first.mID, ref.mObject.mID);

    try first.Delete(engine_context);
    try world.EndFrame(world.GameWorld());
    try std.testing.expect(!ref.mObject.IsActive());
    const reloaded = try ref.Get(engine_context, where);
    try std.testing.expect(reloaded.IsActive());
    try std.testing.expectEqual(object.GetUUID(), reloaded.GetUUID());
}

test "each file ref type is its own kind of variable, with a table entry for its object type" {
    try std.testing.expectEqual(ScriptABI.FieldKind.EntityRef, ScriptABI.FieldKind.Of(EntityRef).?);
    try std.testing.expectEqual(ScriptABI.FieldKind.SceneRef, ScriptABI.FieldKind.Of(SceneRef).?);
    try std.testing.expectEqual(ScriptABI.FieldKind.PlayerRef, ScriptABI.FieldKind.Of(PlayerRef).?);
    try std.testing.expectEqual(ScriptABI.FieldKind.GameContextRef, ScriptABI.FieldKind.Of(GameContextRef).?);
    try std.testing.expectEqual(ScriptABI.FieldKind.SceneRef, MenuExports.info.Fields()[1].mKind);
}

test "Get loads the file once and keeps its UUID, Spawn makes copies without one, for all four object types" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const source = world.SourceWorld();

    try CheckGetAndSpawn(world, EntityRef, try world.mSource.CreateEntity(engine_context, Entity.DefaultConfig), "a.imen", world.mLevel);
    try CheckGetAndSpawn(world, SceneRef, try source.NewScene(engine_context, .GameLayer, Scene.DefaultConfig), "a.imsc", world.GameWorld());
    try CheckGetAndSpawn(world, PlayerRef, try source.CreatePlayer(engine_context, Player.DefaultConfig), "a.impl", world.GameWorld());
    try CheckGetAndSpawn(world, GameContextRef, try source.CreateGameContext(engine_context, GameContext.DefaultConfig), "a.imgc", world.GameWorld());
}

test "with no file Get hands back the object it has, and with nothing at all both are an error" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    var ref: SceneRef = .uninit;
    try std.testing.expectError(error.NoFileSet, ref.Get(engine_context, world.GameWorld()));
    try std.testing.expectError(error.NoFileSet, ref.Spawn(engine_context, world.GameWorld()));

    ref.mObject = world.mLevel;
    try std.testing.expectEqual(world.mLevel.mID, (try ref.Get(engine_context, world.GameWorld())).mID);
    try std.testing.expectError(error.NoFileSet, ref.Spawn(engine_context, world.GameWorld()));
}

test "file refs are saved by path and UUID, each part left out when unset, and read back" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const engine_allocator = engine_context.EngineAllocator();

    var script_asset = try world.ScriptAssetFor(&MenuExports.info);
    defer script_asset.ReleaseAsset();
    _, const script = try world.EntityWithScript(script_asset);

    const pause_scene = try world.GameWorld().NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    var scene_file = try world.SaveFile(pause_scene, "pause.imsc");
    defer scene_file.ReleaseAsset();
    var player_file = try world.SaveFile(try world.SourceWorld().CreatePlayer(engine_context, Player.DefaultConfig), "hero.impl");
    defer player_file.ReleaseAsset();
    const game_context = try world.GameWorld().CreateGameContext(engine_context, GameContext.DefaultConfig);

    try ScriptValues.Set(script, "mScene", SceneRef{ .mFile = scene_file, .mObject = pause_scene });
    try ScriptValues.Set(script, "mPlayer", PlayerRef{ .mFile = player_file });
    try ScriptValues.Set(script, "mGameContext", GameContextRef{ .mObject = game_context });

    var out: std.Io.Writer.Allocating = .init(engine_allocator);
    defer out.deinit();
    var write_stream: std.json.Stringify = .{ .writer = &out.writer };
    const instance = ScriptValues.InstanceOf(script.GetComponent(ScriptComponent).?).?;
    try ScriptValues.Write(instance.mInfo, instance.mData, &write_stream);

    const parsed = try std.json.parseFromSlice(std.json.Value, engine_allocator, out.written(), .{});
    defer parsed.deinit();
    const values = parsed.value.object;
    try std.testing.expect(values.get("mEntity") == null);
    const saved_scene = values.get("mScene").?.object;
    //the shape every asset reference is written in, which is what the export walk will look for
    try std.testing.expectEqualStrings(scene_file.GetFileMetaData().mRelPath.items, saved_scene.get("File").?.object.get("Path").?.string);
    try std.testing.expectEqualStrings("Eng", saved_scene.get("File").?.object.get("PathType").?.string);
    try std.testing.expect(saved_scene.get("Object") != null);
    try std.testing.expect(values.get("mPlayer").?.object.get("Object") == null);
    try std.testing.expect(values.get("mGameContext").?.object.get("File") == null);

    const scene_refs = world.Refs(scene_file);
    const player_refs = world.Refs(player_file);
    _, const loaded = try world.EntityWithScript(script_asset);
    try ScriptValues.Read(engine_context, loaded, parsed.value);
    try std.testing.expectEqual(scene_refs + 1, world.Refs(scene_file));
    try std.testing.expectEqual(player_refs + 1, world.Refs(player_file));

    //the file straight away, the object once it is looked for
    const read = MenuOf(loaded);
    try std.testing.expectEqual(scene_file.mID, read.mScene.mFile.mID);
    try std.testing.expectEqual(player_file.mID, read.mPlayer.mFile.mID);
    try std.testing.expectEqual(Scene.NullObject, read.mScene.mObject.mID);
    engine_context.mSerializer.ResolveUUIDs();
    try std.testing.expectEqual(pause_scene.mID, read.mScene.mObject.mID);
    try std.testing.expectEqual(game_context.mID, read.mGameContext.mObject.mID);
    try std.testing.expect(!read.mEntity.IsSet());
    try std.testing.expect(!read.mPlayer.mObject.IsActive());
}

test "a file that is missing, or isn't the variable's kind, leaves it unset" {
    //the warnings are expected; kept off the build runner's output (see TmplTests)
    std.testing.log_level = .err;
    defer std.testing.log_level = .warn;
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const engine_allocator = engine_context.EngineAllocator();

    var script_asset = try world.ScriptAssetFor(&MenuExports.info);
    defer script_asset.ReleaseAsset();
    _, const script = try world.EntityWithScript(script_asset);
    var scene_file = try world.SaveFile(world.mSource, "kept.imsc");
    defer scene_file.ReleaseAsset();
    const refs = world.Refs(scene_file);

    const json = try std.fmt.allocPrint(engine_allocator,
        \\{{"mScene": {{"File": {{"Path": "no/such/file.imsc", "PathType": "Eng"}}}},
        \\ "mPlayer": {{"File": {{"Path": "{s}", "PathType": "Eng"}}}},
        \\ "mEntity": 7}}
    , .{scene_file.GetFileMetaData().mRelPath.items});
    defer engine_allocator.free(json);
    const parsed = try std.json.parseFromSlice(std.json.Value, engine_allocator, json, .{});
    defer parsed.deinit();
    try ScriptValues.Read(engine_context, script, parsed.value);

    try std.testing.expect(!MenuOf(script).mScene.IsSet());
    try std.testing.expect(!MenuOf(script).mPlayer.IsSet());
    try std.testing.expect(!MenuOf(script).mEntity.IsSet());
    try std.testing.expectEqual(refs, world.Refs(scene_file));
}

test "a file ref's reference follows it through Set, Play's world copy, a duplicate and its owner going" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const sim_world = &engine_context.mSimulateWorld;

    var script_asset = try world.ScriptAssetFor(&MenuExports.info);
    defer script_asset.ReleaseAsset();
    const entity, const script = try world.EntityWithScript(script_asset);
    var file = try world.SaveFile(world.mSource, "first.imsc");
    defer file.ReleaseAsset();
    var other_file = try world.SaveFile(world.mSource, "other.imsc");
    defer other_file.ReleaseAsset();

    //the caller keeps its reference and the variable has one of its own, the one it had given back
    try ScriptValues.Set(script, "mScene", SceneRef{ .mFile = other_file });
    try std.testing.expectEqual(@as(usize, 2), world.Refs(other_file));
    try ScriptValues.Set(script, "mScene", SceneRef{ .mFile = file, .mObject = world.mLevel });
    try std.testing.expectEqual(@as(usize, 1), world.Refs(other_file));
    try std.testing.expectEqual(@as(usize, 2), world.Refs(file));

    //the copy has its own reference, and its object points into the copy
    try engine_context.mGameWorld.Copy(engine_context, sim_world);
    try std.testing.expectEqual(@as(usize, 3), world.Refs(file));
    const sim_menu = MenuOf(sim_world.GetEntity(script.mID));
    try std.testing.expectEqual(file.mID, sim_menu.mScene.mFile.mID);
    try std.testing.expect(sim_menu.mScene.mObject.mManager == sim_world);
    sim_world.clearAndFree(engine_context, .All);
    try std.testing.expectEqual(@as(usize, 2), world.Refs(file));

    //so does a duplicate's
    const copy = try entity.Duplicate(engine_context);
    try std.testing.expectEqual(@as(usize, 3), world.Refs(file));
    try std.testing.expectEqual(file.mID, MenuOf(FirstScript(copy)).mScene.mFile.mID);
    try copy.Delete(engine_context);
    try world.EndFrame(world.GameWorld());
    try std.testing.expectEqual(@as(usize, 2), world.Refs(file));

    try entity.Delete(engine_context);
    try world.EndFrame(world.GameWorld());
    try std.testing.expectEqual(@as(usize, 1), world.Refs(file));
}

test "a copy's file ref points its object at the copy's own or clears it, and always keeps the file" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    var script_asset = try world.ScriptAssetFor(&MenuExports.info);
    defer script_asset.ReleaseAsset();
    const entity, const script = try world.EntityWithScript(script_asset);
    const child = try entity.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    var file = try world.SaveFile(try world.mSource.CreateEntity(engine_context, Entity.DefaultConfig), "child.imen");
    defer file.ReleaseAsset();
    try ScriptValues.Set(script, "mEntity", EntityRef{ .mFile = file, .mObject = child });
    //a scene from another world, as one in a template's world is to its copy
    try ScriptValues.Set(script, "mScene", SceneRef{ .mObject = world.mSource });

    const copy = try entity.Duplicate(engine_context);
    const copy_menu = MenuOf(FirstScript(copy));
    var copy_children = copy.GetIterator(.Child);
    try std.testing.expectEqual(copy_children.next().?.mID, copy_menu.mEntity.mObject.mID);
    try std.testing.expectEqual(file.mID, copy_menu.mEntity.mFile.mID);
    try std.testing.expectEqual(Scene.NullObject, copy_menu.mScene.mObject.mID);
}

test "a new build keeps a file ref still in it with its reference, and gives back the reference of one that is not" {
    const world = try TestWorld.Init();
    defer world.Deinit();

    var kept_file = try world.SaveFile(world.mSource, "kept.imsc");
    defer kept_file.ReleaseAsset();
    var changed_file = try world.SaveFile(world.mSource, "changed.impl");
    defer changed_file.ReleaseAsset();
    var gone_file = try world.SaveFile(world.mSource, "gone.imen");
    defer gone_file.ReleaseAsset();
    kept_file.RetainAsset();
    changed_file.RetainAsset();
    gone_file.RetainAsset();

    var old_value: Menu = .{
        .mScene = .{ .mFile = kept_file },
        .mPlayer = .{ .mFile = changed_file },
        .mEntity = .{ .mFile = gone_file },
    };
    var new_value: MenuEdited = .{};
    ScriptValues.CarryOver(&MenuExports.info, @ptrCast(&old_value), &MenuEditedExports.info, @ptrCast(&new_value));
    defer new_value.mScene.Release();
    ScriptValues.ReleaseDropped(&MenuExports.info, @ptrCast(&old_value), &MenuEditedExports.info);

    try std.testing.expectEqual(kept_file.mID, new_value.mScene.mFile.mID);
    try std.testing.expectEqual(@as(usize, 2), world.Refs(kept_file));
    try std.testing.expectEqual(@as(f32, 0.5), new_value.mPlayer);
    try std.testing.expectEqual(@as(usize, 1), world.Refs(changed_file));
    try std.testing.expectEqual(@as(usize, 1), world.Refs(gone_file));
}

/// The first widget under `widget` whose drop target `wanted` says yes to
fn FindBox(widget: Entity, comptime wanted: fn (DropTargetComponent) bool) ?Entity {
    var children = widget.GetIterator(.Child);
    while (children.next()) |child| {
        if (child.GetComponent(DropTargetComponent)) |drop_target| {
            if (wanted(drop_target.*)) return child;
        }
        if (FindBox(child, wanted)) |found| return found;
    }
    return null;
}

fn TakesFiles(drop_target: DropTargetComponent) bool {
    return drop_target.mExtensions.len > 0;
}

fn TakesObjects(drop_target: DropTargetComponent) bool {
    return drop_target.mObjectKind != null;
}

fn TextIn(box: Entity) []const u8 {
    return UIManager.LabelOf(box).?.GetComponent(TextComponent).?.mText.items;
}

test "a file ref's rows take a dropped file of its kind and a hierarchy row, and Clear gives the file back" {
    //the turned-down drop's warning is expected; kept off the build runner's output (see TmplTests)
    std.testing.log_level = .err;
    defer std.testing.log_level = .warn;
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    var script_asset = try world.ScriptAssetFor(&MenuExports.info);
    defer script_asset.ReleaseAsset();
    _, const script = try world.EntityWithScript(script_asset);
    var wrong_file = try world.SaveFile(world.mSource, "hero.impl");
    defer wrong_file.ReleaseAsset();

    const panel = try world.mUIScene.CreateEntity(engine_context, Entity.DefaultConfig);
    try ScriptValues.BuildFields(engine_context, panel, panel, script, NO_SCRIPTS);
    //the first of each is mEntity's, which takes .imen files
    const file_box = FindBox(panel, TakesFiles).?;
    const object_box = FindBox(panel, TakesObjects).?;

    try world.Drop(try world.FileTile(wrong_file.GetFileMetaData().mRelPath.items), file_box);
    try std.testing.expect(!MenuOf(script).mEntity.IsSet());

    var entity_file = try world.SaveFile(try world.mSource.CreateEntity(engine_context, Entity.DefaultConfig), "door.imen");
    defer entity_file.ReleaseAsset();
    const refs = world.Refs(entity_file);
    try world.Drop(try world.FileTile(entity_file.GetFileMetaData().mRelPath.items), file_box);
    try std.testing.expectEqual(entity_file.mID, MenuOf(script).mEntity.mFile.mID);
    try std.testing.expectEqual(refs + 1, world.Refs(entity_file));
    try world.ShowFields();
    try std.testing.expectEqualStrings("door", TextIn(file_box));

    const door = try world.mLevel.CreateEntity(engine_context, Entity.DefaultConfig);
    try world.Drop(try world.ObjectRow(door), object_box);
    try std.testing.expectEqual(door.mID, MenuOf(script).mEntity.mObject.mID);

    try world.Clear(file_box);
    try std.testing.expectEqual(AssetHandle.NullObject, MenuOf(script).mEntity.mFile.mID);
    try std.testing.expectEqual(refs, world.Refs(entity_file));
}
