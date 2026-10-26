//! The Project Settings panel in the editor's own UI (EditorPanels/ProjectSettingsPanel.zig): its fields show the
//! project's name, window icon and entries ("Not set" for a file that isn't), a file dropped on a box becomes that
//! setting when it is the right kind of file, the name typed in renames the game, and each button has its action. No window, file dialog or renderer
//! needed. Run with `zig build test-engine`.
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
        engine_context._Internal.ThreadedIO = std.Io.Threaded.init(engine_context._Internal.EngineGPA.allocator(), .{
            .concurrent_limit = .nothing,
            .async_limit = .nothing,
        });
        //the audio settings are one of the project's settings owners
        try engine_context.mAudioManager.InitMixer(engine_context);
        try engine_context.mUIManager.Init(engine_context.EngineAllocator());
        try engine_context.mEditorWorld.Init(engine_context.EngineAllocator());
        self.mScene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
        self.mPanel = try ProjectSettingsPanel.Build(engine_context, self.mScene, .{ .StockScripts = false });

        const project_folder = try self.mTmpDir.dir.realPathFileAlloc(engine_context.Io(), ".", engine_context.FrameAllocator());
        try engine_context.mProject.New(engine_context, project_folder);
        return self;
    }

    fn Deinit(self: *TestEngine) void {
        const engine_context = self.mEngineContext;
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        engine_context.mAudioManager.DeinitMixer(engine_context);
        engine_context.mProject.Deinit(engine_context);
        engine_context.mSerializer.Deinit(engine_context.EngineAllocator());
        _ = engine_context._Internal.EngineGPA.deinit();
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
        _ = try file.AddComponent(engine_context, try FileRefComponent.Init(engine_context, rel_path, .Prj));
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

    const scene_path = try engine_context.mProject.GetAbsPath(engine_context.FrameAllocator(), "Scenes/Main.imsc");
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

    try panel.mName.GetComponentMut(TextComponent).?.SetText(engine_context, "Space Pong");
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
