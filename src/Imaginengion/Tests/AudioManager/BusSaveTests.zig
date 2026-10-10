//! Saves the bus tree with the project's audio settings and reads it back into a second, fresh engine, the way opening
//! a project does. Voices and buses only, through AudioManager.InitMixer: no sound card, window or renderer needed.
//! Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Project = @import("../../Core/Project.zig");
const TextSerializer = @import("../../Serializer/TextSerializer.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const Player = @import("../../ECSObjects/Player.zig");
const GameContext = @import("../../ECSObjects/GameContext.zig");
const Bus = @import("../../ECSObjects/Bus.zig");
const VComponents = @import("../../ECSComponents/VComponents.zig");
const VolumeComponent = VComponents.VolumeComponent;
const UUIDComponent = VComponents.UUIDComponent;
const AudioComponent = @import("../../ECSComponents/EComponents.zig").AudioComponent;

const TestEngine = struct {
    mEngineContext: *EngineContext,
    mTmpDir: std.testing.TmpDir,

    fn Init() !*TestEngine {
        const self = try std.heap.page_allocator.create(TestEngine);
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
        try engine_context.mAudioManager.InitMixer(engine_context);
        return self;
    }

    fn Deinit(self: *TestEngine) void {
        const engine_context = self.mEngineContext;
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mAudioManager.DeinitMixer(engine_context);
        engine_context.mProject.Deinit(engine_context);
        engine_context.mSerializer.Deinit(engine_context.EngineAllocator());
        _ = engine_context._Internal.EngineGPA.deinit();
        self.mTmpDir.cleanup();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    fn AudioManager(self: *TestEngine) *@FieldType(EngineContext, "mAudioManager") {
        return &self.mEngineContext.mAudioManager;
    }

    /// This test's temporary folder as an absolute path, which is what a project is opened with
    fn TmpDirAbsPath(self: *TestEngine) ![]const u8 {
        return try self.mTmpDir.dir.realPathFileAlloc(self.mEngineContext.Io(), ".", self.mEngineContext.FrameAllocator());
    }

    /// A path in this test's temporary folder, relative to the working directory like the serializer expects
    fn FilePath(self: *TestEngine, file_name: []const u8) ![]const u8 {
        return std.fmt.allocPrint(self.mEngineContext.FrameAllocator(), ".zig-cache/tmp/{s}/{s}", .{ self.mTmpDir.sub_path, file_name });
    }
};

/// The audio settings as they would be written to ProjectSettings/Audio.json
fn SaveAudioSettings(engine: *TestEngine) ![]const u8 {
    const engine_context = engine.mEngineContext;
    var out: std.Io.Writer.Allocating = .init(engine_context.FrameAllocator());
    var write_stream: std.json.Stringify = .{ .writer = &out.writer };
    try engine.AudioManager().SaveProjectSettings(engine_context, &write_stream);
    return out.written();
}

fn LoadAudioSettings(engine: *TestEngine, contents: []const u8) !void {
    const engine_context = engine.mEngineContext;
    var scanner = std.json.Scanner.initCompleteInput(engine_context.FrameAllocator(), contents);
    defer scanner.deinit();
    try engine.AudioManager().LoadProjectSettings(engine_context, &scanner);
}

fn NewBus(engine: *TestEngine, parent: Bus, name: []const u8, volume: f32) !Bus {
    const engine_context = engine.mEngineContext;
    const bus = try parent.CreateChild(engine_context, .Entity, Bus.DefaultConfig);
    const name_component = bus.GetComponent(VComponents.NameComponent).?;
    name_component.mName.clearRetainingCapacity();
    try name_component.mName.appendSlice(engine_context.EngineAllocator(), name);
    bus.SetVolume(volume);
    return bus;
}

fn ChildNamed(parent: Bus, name: []const u8) ?Bus {
    var child_iter = parent.GetIterator(.Child);
    while (child_iter.next()) |child| {
        if (std.mem.eql(u8, child.GetName(), name)) return child;
    }
    return null;
}

fn ChildCount(parent: Bus) usize {
    var count: usize = 0;
    var child_iter = parent.GetIterator(.Child);
    while (child_iter.next()) |_| count += 1;
    return count;
}

fn Volume(bus: Bus) f32 {
    return bus.GetComponent(VolumeComponent).?.mVolume;
}

/// Checks a loaded bus is the same bus as the saved one: same name, volume and UUID, and the same children
fn ExpectSameTree(saved: Bus, loaded: Bus) !void {
    try std.testing.expectEqualStrings(saved.GetName(), loaded.GetName());
    try std.testing.expectEqual(Volume(saved), Volume(loaded));
    try std.testing.expectEqual(saved.GetUUID(), loaded.GetUUID());
    try std.testing.expectEqual(ChildCount(saved), ChildCount(loaded));

    var child_iter = saved.GetIterator(.Child);
    while (child_iter.next()) |saved_child| {
        const loaded_child = ChildNamed(loaded, saved_child.GetName()) orelse return error.MissingBus;
        try ExpectSameTree(saved_child, loaded_child);
    }
}

test "a bus tree round trips through the audio settings" {
    const saved_engine = try TestEngine.Init();
    defer saved_engine.Deinit();

    const master = saved_engine.AudioManager().GetMasterBus();
    master.SetVolume(0.8);
    const sfx = try NewBus(saved_engine, master, "SFX", 0.5);
    _ = try NewBus(saved_engine, sfx, "Footsteps", 0.25);
    _ = try NewBus(saved_engine, master, "Music", 0.7);

    const settings = try SaveAudioSettings(saved_engine);

    const loaded_engine = try TestEngine.Init();
    defer loaded_engine.Deinit();
    try LoadAudioSettings(loaded_engine, settings);

    try ExpectSameTree(master, loaded_engine.AudioManager().GetMasterBus());
}

test "loaded buses can be found by their UUID" {
    const saved_engine = try TestEngine.Init();
    defer saved_engine.Deinit();
    const sfx = try NewBus(saved_engine, saved_engine.AudioManager().GetMasterBus(), "SFX", 0.5);

    const loaded_engine = try TestEngine.Init();
    defer loaded_engine.Deinit();
    try LoadAudioSettings(loaded_engine, try SaveAudioSettings(saved_engine));

    const found = loaded_engine.AudioManager().GetBusByUUID(sfx.GetUUID()) orelse return error.BusNotFound;
    try std.testing.expectEqualStrings("SFX", found.GetName());
}

test "an AudioComponent's bus is saved as its UUID and comes back once the buses are loaded" {
    const saved_engine = try TestEngine.Init();
    defer saved_engine.Deinit();
    const saved_context = saved_engine.mEngineContext;

    const master = saved_engine.AudioManager().GetMasterBus();
    const sfx = try NewBus(saved_engine, master, "SFX", 0.5);

    const scene = try saved_context.mEditorWorld.NewScene(saved_context, .GameLayer, Scene.DefaultConfig);
    const on_sfx = try scene.CreateEntity(saved_context, Entity.DefaultConfig);
    _ = try on_sfx.AddComponent(saved_context, AudioComponent{ .mBus = sfx, .mVolume = 0.3 });
    const on_master = try scene.CreateEntity(saved_context, Entity.DefaultConfig);
    _ = try on_master.AddComponent(saved_context, AudioComponent{ .mBus = master });

    const on_sfx_path = try saved_engine.FilePath("OnSfx.imen");
    const on_master_path = try saved_engine.FilePath("OnMaster.imen");
    try TextSerializer.SerializeECSObject(saved_context, on_sfx, on_sfx_path);
    try TextSerializer.SerializeECSObject(saved_context, on_master, on_master_path);
    const settings = try SaveAudioSettings(saved_engine);

    //the order opening a project and then a scene has: buses first, then what points at them
    const loaded_engine = try TestEngine.Init();
    defer loaded_engine.Deinit();
    const loaded_context = loaded_engine.mEngineContext;
    try LoadAudioSettings(loaded_engine, settings);

    const loaded_scene = try loaded_context.mEditorWorld.NewScene(loaded_context, .GameLayer, Scene.DefaultConfig);
    const loaded_on_sfx = try loaded_scene.CreateEntity(loaded_context, Entity.BlankConfig);
    try TextSerializer.DeserializeECSObj(loaded_context, loaded_on_sfx, on_sfx_path);
    const loaded_on_master = try loaded_scene.CreateEntity(loaded_context, Entity.BlankConfig);
    try TextSerializer.DeserializeECSObj(loaded_context, loaded_on_master, on_master_path);
    loaded_context.mSerializer.ResolveUUIDs();

    const loaded_sfx_component = loaded_on_sfx.GetComponent(AudioComponent).?;
    try std.testing.expect(loaded_sfx_component.mBus.IsActive());
    try std.testing.expectEqual(sfx.GetUUID(), loaded_sfx_component.mBus.GetUUID());
    try std.testing.expectEqual(0.3, loaded_sfx_component.mVolume);

    //Master is not written: it loads as unset, which plays into Master
    const loaded_master_component = loaded_on_master.GetComponent(AudioComponent).?;
    try std.testing.expect(!loaded_master_component.mBus.IsIDValid());
    const loaded_audio_manager = loaded_engine.AudioManager();
    try std.testing.expectEqual(loaded_audio_manager.GetMasterBus().mID, loaded_audio_manager.ResolveBus(loaded_master_component.mBus.mID));
}

test "a scene, player or game context's AudioComponent gets its bus back too" {
    const saved_engine = try TestEngine.Init();
    defer saved_engine.Deinit();
    const saved_context = saved_engine.mEngineContext;
    const sfx = try NewBus(saved_engine, saved_engine.AudioManager().GetMasterBus(), "SFX", 0.5);

    const scene = try saved_context.mEditorWorld.NewScene(saved_context, .GameLayer, Scene.DefaultConfig);
    const player = try saved_context.mEditorWorld.CreatePlayer(saved_context, Player.DefaultConfig);
    const game_context = try saved_context.mEditorWorld.CreateGameContext(saved_context, GameContext.DefaultConfig);
    _ = try scene.AddComponent(saved_context, AudioComponent{ .mBus = sfx });
    _ = try player.AddComponent(saved_context, AudioComponent{ .mBus = sfx });
    _ = try game_context.AddComponent(saved_context, AudioComponent{ .mBus = sfx });

    const scene_path = try saved_engine.FilePath("Level.imsc");
    const player_path = try saved_engine.FilePath("Hero.impl");
    const game_context_path = try saved_engine.FilePath("Rules.imgc");
    try TextSerializer.SerializeECSObject(saved_context, scene, scene_path);
    try TextSerializer.SerializeECSObject(saved_context, player, player_path);
    try TextSerializer.SerializeECSObject(saved_context, game_context, game_context_path);
    const settings = try SaveAudioSettings(saved_engine);

    const loaded_engine = try TestEngine.Init();
    defer loaded_engine.Deinit();
    const loaded_context = loaded_engine.mEngineContext;
    try LoadAudioSettings(loaded_engine, settings);

    const loaded_scene = try loaded_context.mEditorWorld.mSManager.CreateBlankScene(loaded_context);
    try TextSerializer.DeserializeECSObj(loaded_context, loaded_scene, scene_path);
    const loaded_player = try loaded_context.mEditorWorld.CreatePlayer(loaded_context, Player.BlankConfig);
    try TextSerializer.DeserializeECSObj(loaded_context, loaded_player, player_path);
    const loaded_game_context = try loaded_context.mEditorWorld.CreateGameContext(loaded_context, GameContext.BlankConfig);
    try TextSerializer.DeserializeECSObj(loaded_context, loaded_game_context, game_context_path);
    loaded_context.mSerializer.ResolveUUIDs();

    try std.testing.expectEqual(sfx.GetUUID(), loaded_scene.GetComponent(AudioComponent).?.mBus.GetUUID());
    try std.testing.expectEqual(sfx.GetUUID(), loaded_player.GetComponent(AudioComponent).?.mBus.GetUUID());
    try std.testing.expectEqual(sfx.GetUUID(), loaded_game_context.GetComponent(AudioComponent).?.mBus.GetUUID());
}

test "a project saves its buses and opening it in a fresh engine brings them back" {
    const saved_engine = try TestEngine.Init();
    defer saved_engine.Deinit();
    const saved_context = saved_engine.mEngineContext;

    const project_folder = try saved_engine.TmpDirAbsPath();
    try saved_context.mProject.New(saved_context, project_folder);

    //a new project starts with just Master
    const master = saved_engine.AudioManager().GetMasterBus();
    try std.testing.expectEqual(0, ChildCount(master));

    const sfx = try NewBus(saved_engine, master, "SFX", 0.5);
    _ = try NewBus(saved_engine, sfx, "Weapons", 0.9);
    try saved_context.mProject.Save(saved_context);

    //the project file is named after the folder, and each owner has its own settings file
    const project_file_name = try std.fmt.allocPrint(saved_context.FrameAllocator(), "{s}{s}", .{ std.fs.path.basename(project_folder), Project.FILE_EXTENSION });
    try saved_engine.mTmpDir.dir.access(saved_context.Io(), project_file_name, .{});
    try saved_engine.mTmpDir.dir.access(saved_context.Io(), Project.SETTINGS_FOLDER ++ "/Audio.json", .{});

    const loaded_engine = try TestEngine.Init();
    defer loaded_engine.Deinit();
    const loaded_context = loaded_engine.mEngineContext;
    const project_file_path = try std.fs.path.join(loaded_context.FrameAllocator(), &.{ project_folder, project_file_name });
    try loaded_context.mProject.Open(loaded_context, project_file_path);

    try std.testing.expect(loaded_context.mProject.IsOpen());
    try ExpectSameTree(master, loaded_engine.AudioManager().GetMasterBus());
}

test "a project without audio settings opens with just Master" {
    const engine = try TestEngine.Init();
    defer engine.Deinit();
    const engine_context = engine.mEngineContext;

    //a project from before audio settings existed: only its project file
    try engine.mTmpDir.dir.writeFile(engine_context.Io(), .{ .sub_path = "Old.imprj", .data = "{\"Name\": \"Old\", \"Version\": 1}" });
    const project_file_path = try std.fs.path.join(engine_context.FrameAllocator(), &.{ try engine.TmpDirAbsPath(), "Old.imprj" });
    try engine_context.mProject.Open(engine_context, project_file_path);

    const master = engine.AudioManager().GetMasterBus();
    try std.testing.expectEqual(0, ChildCount(master));
    try std.testing.expectEqual(1.0, Volume(master));
    try std.testing.expectEqualStrings("Master", master.GetName());
}
