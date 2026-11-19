//! The Project Settings panel in the editor's own UI (EditorPanels/ProjectSettingsPanel.zig): its fields show the
//! project's name, window icon and entries ("Not set" for a file that isn't), a file dropped on a box becomes that
//! setting when it is the right kind of file, the name typed in renames the game, each button has its action, and the
//! target platforms have a row each with their budgets. No window, file dialog or renderer needed. Run with
//! `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const Project = @import("../../Core/Project.zig");
const ProjectSettingsPanel = @import("../../EditorPanels/ProjectSettingsPanel.zig");
const WidgetActions = @import("../../UI/WidgetActions.zig");
const UIManager = @import("../../UI/UIManager.zig");
const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const TextComponent = EntityComponents.TextComponent;
const FileRefComponent = EntityComponents.FileRefComponent;

const TestEngine = struct {
    mEngineContext: *EngineContext,
    mTmpDir: std.testing.TmpDir,
    mScene: Scene = undefined,
    mPanel: ProjectSettingsPanel = .{},

    fn Init() !*TestEngine {
        const self = try std.heap.page_allocator.create(TestEngine);
        self.* = .{
            .mEngineContext = try std.heap.page_allocator.create(EngineContext),
            .mTmpDir = std.testing.tmpDir(.{}),
        };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        //the project's files go through the context's Io, which forwards to this
        engine_context._Internal.ThreadPool = std.Io.Threaded.init(engine_context._Internal.KeepHeap.allocator(), .{
            .concurrent_limit = .nothing,
            .async_limit = .nothing,
        });
        //the audio settings are one of the project's settings owners
        try engine_context.mAudioManager.InitMixer(engine_context);
        try engine_context.mUIManager.Init(engine_context);
        try engine_context.mEditorWorld.Init(engine_context);
        self.mScene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
        self.mPanel = try ProjectSettingsPanel.Build(engine_context, self.mScene, .{ .StockScripts = false });

        const project_folder = try self.mTmpDir.dir.realPathFileAlloc(engine_context.Io(), ".", engine_context.Scratch());
        try engine_context.mProject.New(engine_context, project_folder);
        return self;
    }

    fn Deinit(self: *TestEngine) void {
        const engine_context = self.mEngineContext;
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        engine_context.mAudioManager.DeinitMixer(engine_context);
        engine_context.mProject.Deinit(engine_context);
        engine_context.mSerializer.Deinit(engine_context.Keep());
        _ = engine_context._Internal.KeepHeap.deinit();
        self.mTmpDir.cleanup();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    /// What `box`'s label says
    fn Shown(box: Entity) []const u8 {
        return UIManager.LabelOf(box).?.GetComponent(TextComponent).?.mText.items;
    }

    /// A Content Browser file standing for rel_path, dropped on `box`
    fn DropOn(self: *TestEngine, box: Entity, rel_path: []const u8) !void {
        const engine_context = self.mEngineContext;
        const file = try self.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
        _ = try file.AddComponent(engine_context, try FileRefComponent.Init(file.KeepFor(FileRefComponent), rel_path, .Prj));
        try self.mPanel.OnDrop(engine_context, box, .{ .mSource = file, .mPosition = .{ .x = 0, .y = 0, .z = 0 } });
    }
};

test "the fields show the project's settings, Not set for a file that isn't, and follow them when they change" {
    const engine = try TestEngine.Init();
    defer engine.Deinit();
    const engine_context = engine.mEngineContext;
    const panel = &engine.mPanel;
    try WidgetActions.OpenWindow(engine_context, panel.mWindow);

    try panel.Update(engine_context);
    try std.testing.expectEqualStrings(engine_context.mProject.GetName(), TestEngine.Shown(panel.mName));
    try std.testing.expectEqualStrings("Not set", TestEngine.Shown(panel.mIcon.Box));
    for (panel.mEntries.values) |row| try std.testing.expectEqualStrings("Not set", TestEngine.Shown(row.Box));

    const scene_path = try engine_context.mProject.GetAbsPath(engine_context.Scratch(), "Scenes/Main.imsc");
    try engine_context.mProject.SetEntry(engine_context, .Scene, scene_path);
    try panel.Update(engine_context);
    try std.testing.expectEqualStrings("Scenes/Main.imsc", TestEngine.Shown(panel.mEntries.get(.Scene).Box));
    try std.testing.expectEqualStrings("Not set", TestEngine.Shown(panel.mEntries.get(.Player).Box));
}

test "a file dropped on a box becomes that setting, only when it is the setting's kind of file" {
    const engine = try TestEngine.Init();
    defer engine.Deinit();
    const engine_context = engine.mEngineContext;
    const panel = &engine.mPanel;

    try engine.DropOn(panel.mEntries.get(.Player).Box, "Players/Hero.impl");
    try std.testing.expectEqualStrings("Players/Hero.impl", engine_context.mProject.GetEntry(.Player));
    //a scene file isn't a game context
    try engine.DropOn(panel.mEntries.get(.GameContext).Box, "Scenes/Main.imsc");
    try std.testing.expectEqualStrings("", engine_context.mProject.GetEntry(.GameContext));

    try engine.DropOn(panel.mIcon.Box, "Art/Icon.png");
    try std.testing.expectEqualStrings("Art/Icon.png", engine_context.mProject.GetWindowIcon());
    //only a PNG is an icon
    try engine.DropOn(panel.mIcon.Box, "Scenes/Main.imsc");
    try std.testing.expectEqualStrings("Art/Icon.png", engine_context.mProject.GetWindowIcon());

    try ProjectSettingsPanel.Run(engine_context, panel.ActionOf(panel.mClearIcon).?);
    try std.testing.expectEqualStrings("", engine_context.mProject.GetWindowIcon());
}

test "the name typed in and kept renames the game, not the project file" {
    const engine = try TestEngine.Init();
    defer engine.Deinit();
    const engine_context = engine.mEngineContext;
    const panel = &engine.mPanel;

    try panel.mName.GetComponentMut(TextComponent).?.SetText(panel.mName.KeepFor(TextComponent), "Space Pong");
    try panel.OnUIEvent(engine_context, .{ .mEntity = panel.mName, .mEvent = .{ .TextSubmitted = .{ .mTarget = panel.mName } } });
    try std.testing.expectEqualStrings("Space Pong", engine_context.mProject.GetName());
    try std.testing.expect(!std.mem.eql(u8, "Space Pong", std.fs.path.stem(engine_context.mProject.mFileName.items)));
}

test "each button has its action" {
    const engine = try TestEngine.Init();
    defer engine.Deinit();
    const panel = &engine.mPanel;

    try std.testing.expectEqual(.Scene, panel.ActionOf(panel.mEntries.get(.Scene).Browse).?.BrowseEntry);
    try std.testing.expectEqual(.GameContext, panel.ActionOf(panel.mEntries.get(.GameContext).Browse).?.BrowseEntry);
    try std.testing.expectEqual(ProjectSettingsPanel.Action.BrowseIcon, panel.ActionOf(panel.mIcon.Browse).?);
    try std.testing.expectEqual(ProjectSettingsPanel.Action.ClearIcon, panel.ActionOf(panel.mClearIcon).?);
    //a box is no button
    try std.testing.expect(panel.ActionOf(panel.mEntries.get(.Scene).Box) == null);
}

fn IsShown(entity: Entity) bool {
    return !entity.GetComponent(EntityComponents.LayoutItemComponent).?.mCollapsed;
}

/// Types `text` into a field and keeps it
fn Submit(engine: *TestEngine, field: Entity, text: []const u8) !void {
    try field.GetComponentMut(TextComponent).?.SetText(field.KeepFor(TextComponent), text);
    try engine.mPanel.OnUIEvent(engine.mEngineContext, .{ .mEntity = field, .mEvent = .{ .TextSubmitted = .{ .mTarget = field } } });
}

test "a target platform has a row with its budgets, rows come and go with platforms, and a budget typed in is kept" {
    const engine = try TestEngine.Init();
    defer engine.Deinit();
    const engine_context = engine.mEngineContext;
    const panel = &engine.mPanel;
    const platforms = &engine_context.mTargetPlatforms;
    try WidgetActions.OpenWindow(engine_context, panel.mWindow);

    //a new project's one platform, the target
    try panel.Update(engine_context);
    try std.testing.expect(IsShown(panel.mPlatforms[0].Row));
    try std.testing.expect(!IsShown(panel.mPlatforms[1].Row));
    try std.testing.expectEqualStrings("PC", TestEngine.Shown(panel.mPlatforms[0].Name));
    try std.testing.expectEqualStrings("Target", TestEngine.Shown(panel.mPlatforms[0].Target));

    try ProjectSettingsPanel.Run(engine_context, panel.ActionOf(panel.mAddPlatform).?);
    try panel.Update(engine_context);
    try std.testing.expect(IsShown(panel.mPlatforms[1].Row));
    try std.testing.expectEqualStrings("Make Target", TestEngine.Shown(panel.mPlatforms[1].Target));

    //typed in: a name, a budget; something that isn't a whole number of MB is shown as it was again
    try Submit(engine, panel.mPlatforms[1].Name, "Switch 2");
    try Submit(engine, panel.mPlatforms[1].CPU, "3072");
    try Submit(engine, panel.mPlatforms[1].Video, "lots");
    try panel.Update(engine_context);
    try std.testing.expectEqualStrings("Switch 2", platforms.GetName(1));
    try std.testing.expectEqual(3072, platforms.Get(1).mCPUMemoryMB);
    try std.testing.expectEqualStrings("4096", TestEngine.Shown(panel.mPlatforms[1].Video));

    try ProjectSettingsPanel.Run(engine_context, panel.ActionOf(panel.mPlatforms[1].Target).?);
    try std.testing.expectEqual(1, platforms.mTarget);
    try ProjectSettingsPanel.Run(engine_context, panel.ActionOf(panel.mPlatforms[0].Remove).?);
    try panel.Update(engine_context);
    try std.testing.expect(!IsShown(panel.mPlatforms[1].Row));
    try std.testing.expectEqualStrings("Switch 2", TestEngine.Shown(panel.mPlatforms[0].Name));
    try std.testing.expectEqualStrings("Target", TestEngine.Shown(panel.mPlatforms[0].Target));

    //saved with the project and read back when it is opened again
    try engine_context.mProject.Save(engine_context);
    const project_file = try engine_context.mProject.GetAbsPath(engine_context.Scratch(), engine_context.mProject.mFileName.items);
    try engine_context.mProject.Open(engine_context, project_file);
    try std.testing.expectEqualStrings("Switch 2", platforms.GetName(platforms.mTarget));
    try std.testing.expectEqual(3072, platforms.Target().mCPUMemoryMB);
}

test "the engine's baseline a game recorded in the project is read, and none is none" {
    const engine = try TestEngine.Init();
    defer engine.Deinit();
    const engine_context = engine.mEngineContext;
    const platforms = &engine_context.mTargetPlatforms;
    const GameMemory = @import("../../Core/GameMemory.zig");

    platforms.RefreshBaseline(engine_context);
    try std.testing.expect(platforms.mRecorded == null);
    try std.testing.expectEqualStrings("", platforms.RecordedOn());

    //what a game built with -Dstats writes
    try engine_context.mProject.GetDirectory().writeFile(engine_context.Io(), .{ .sub_path = GameMemory.BASELINE_FILE, .data = "{\"CPUBytes\": 24195646, \"VideoBytes\": 413760512, \"Measured\": \"2026-11-19\"}" });
    platforms.RefreshBaseline(engine_context);
    try std.testing.expectEqual(24195646, platforms.mRecorded.?.CPU);
    try std.testing.expectEqual(413760512, platforms.mRecorded.?.Video);
    try std.testing.expectEqualStrings("2026-11-19", platforms.RecordedOn());
}
