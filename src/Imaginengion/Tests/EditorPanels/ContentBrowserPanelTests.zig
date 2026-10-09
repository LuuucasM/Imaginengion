//! The Content Browser in the editor's own UI (EditorPanels/ContentBrowserPanel.zig), on a temporary folder: a tile per
//! folder and shown file, folders first and each by name, other files left out, long names shortened, going into a
//! folder and back up by double clicking, a new file showing up, files' tiles carrying their path when dragged, and New
//! Scene Layer from the pane's menu. Also the Scripts panel taking a drop: which object a script type goes on, and a
//! file that isn't a script ignored (adding a real script compiles it, so that part isn't run here). No window or
//! renderer needed. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const ContentBrowserPanel = @import("../../EditorPanels/ContentBrowserPanel.zig");
const ScriptsPanel = @import("../../EditorPanels/ScriptsPanel.zig");
const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const TextComponent = EntityComponents.TextComponent;
const LayoutComponent = EntityComponents.LayoutComponent;
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const DragSourceComponent = EntityComponents.DragSourceComponent;
const FileRefComponent = EntityComponents.FileRefComponent;

const TestBrowser = struct {
    mEngineContext: *EngineContext,
    mTmpDir: std.testing.TmpDir,
    mScene: Scene = undefined,
    mPanel: ContentBrowserPanel = .{},

    fn Init() !*TestBrowser {
        const self = try std.heap.page_allocator.create(TestBrowser);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext), .mTmpDir = std.testing.tmpDir(.{}) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        //folders are listed through the context's Io, which forwards to this
        engine_context._Internal.ThreadedIO = std.Io.Threaded.init(engine_context._Internal.EngineGPA.allocator(), .{
            .concurrent_limit = .nothing,
            .async_limit = .nothing,
        });
        try engine_context.mUIManager.Init(engine_context.EngineAllocator());
        try engine_context.mEditorWorld.Init(engine_context.EngineAllocator());
        self.mScene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
        //the shell's pane
        const page = try self.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
        _ = try page.AddComponent(engine_context, LayoutComponent{ .mDirection = .Column });
        self.mPanel = try ContentBrowserPanel.Build(engine_context, page, .{}, .{ .StockScripts = false });
        return self;
    }

    fn Deinit(self: *TestBrowser) void {
        const engine_context = self.mEngineContext;
        self.mPanel.Deinit(engine_context.EngineAllocator());
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
        self.mTmpDir.cleanup();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    fn Io(self: *TestBrowser) std.Io {
        return self.mEngineContext._Internal.ThreadedIO.io();
    }

    fn WriteFile(self: *TestBrowser, sub_path: []const u8) !void {
        try self.mTmpDir.dir.writeFile(self.Io(), .{ .sub_path = sub_path, .data = "" });
    }

    /// Shows the temporary folder as the project
    fn Open(self: *TestBrowser) !void {
        const root = try self.mTmpDir.dir.realPathFileAlloc(self.Io(), ".", self.mEngineContext.FrameAllocator());
        try self.mPanel.SetRoot(self.mEngineContext, root);
    }

    fn Update(self: *TestBrowser) !void {
        try self.mPanel.Update(self.mEngineContext);
    }

    /// Each tile's shown name
    fn Names(self: *TestBrowser, out: [][]const u8) usize {
        for (self.mPanel.mTiles.items, 0..) |tile, i| {
            var parts = tile.Entity.GetIterator(.Child);
            _ = parts.next().?; //the icon
            if (i < out.len) out[i] = parts.next().?.GetComponent(TextComponent).?.mText.items;
        }
        return self.mPanel.mTiles.items.len;
    }

    fn Tile(self: *TestBrowser, index: usize) Entity {
        return self.mPanel.mTiles.items[index].Entity;
    }
};

test "a tile per folder and shown file, folders first, each by name, others left out and long names shortened" {
    const browser = try TestBrowser.Init();
    defer browser.Deinit();

    //nothing open yet
    try browser.Update();
    try std.testing.expectEqualStrings("Open a project to see its files", browser.mPanel.mMessage.GetComponent(TextComponent).?.mText.items);

    try browser.mTmpDir.dir.createDirPath(browser.Io(), "Sprites");
    try browser.WriteFile("Mover.zig");
    try browser.WriteFile("Level.imsc");
    try browser.WriteFile("hero.png");
    try browser.WriteFile("notes.txt");
    try browser.WriteFile("AVeryLongFileName.png");
    try browser.Open();
    try browser.Update();

    var names: [16][]const u8 = undefined;
    try std.testing.expectEqual(@as(usize, 5), browser.Names(&names));
    try std.testing.expectEqualStrings("Sprites", names[0]);
    try std.testing.expectEqualStrings("AVeryLong...", names[1]);
    try std.testing.expectEqualStrings("Level.imsc", names[2]);
    try std.testing.expectEqualStrings("Mover.zig", names[3]);
    try std.testing.expectEqualStrings("hero.png", names[4]);
    try std.testing.expect(browser.mPanel.mMessage.GetComponent(LayoutItemComponent).?.mCollapsed);

    //a file's tile carries its path when dragged, a folder's isn't dragged at all
    try std.testing.expect(!browser.Tile(0).HasComponent(DragSourceComponent));
    try std.testing.expect(browser.Tile(3).HasComponent(DragSourceComponent));
    try std.testing.expectEqualStrings("Mover.zig", browser.Tile(3).GetComponent(FileRefComponent).?.mRelPath.items);

    //nothing changed: not built again. A new file: built again with it
    const grid = browser.mPanel.mGrid.?;
    try browser.Update();
    try std.testing.expectEqual(grid.mID, browser.mPanel.mGrid.?.mID);
    try browser.WriteFile("Jump.wav");
    try browser.Update();
    try std.testing.expect(browser.mPanel.mGrid.?.mID != grid.mID);
    try std.testing.expectEqual(@as(usize, 6), browser.Names(&names));
}

test "double clicking a folder goes into it, Back comes up again, and a single click does nothing" {
    const browser = try TestBrowser.Init();
    defer browser.Deinit();
    const engine_context = browser.mEngineContext;
    try browser.mTmpDir.dir.createDirPath(browser.Io(), "Sprites");
    try browser.WriteFile("Sprites/hero.png");
    try browser.Open();
    try browser.Update();
    const root_len = browser.mPanel.CurrentPath().len;

    try std.testing.expect(browser.mPanel.ActionOf(browser.Tile(0), 1) == null);
    const enter = browser.mPanel.ActionOf(browser.Tile(0), 2).?;
    try browser.mPanel.Run(engine_context, enter);
    try browser.Update();
    try std.testing.expect(std.mem.endsWith(u8, browser.mPanel.CurrentPath(), "/Sprites"));

    //Back first, then the folder's file, whose path is from the project's folder
    var names: [8][]const u8 = undefined;
    try std.testing.expectEqual(@as(usize, 2), browser.Names(&names));
    try std.testing.expectEqualStrings("Back", names[0]);
    try std.testing.expectEqualStrings("Sprites/hero.png", browser.Tile(1).GetComponent(FileRefComponent).?.mRelPath.items);

    try browser.mPanel.Run(engine_context, browser.mPanel.ActionOf(browser.Tile(0), 2).?);
    try browser.Update();
    try std.testing.expectEqual(root_len, browser.mPanel.CurrentPath().len);
    try std.testing.expectEqualStrings("Sprites", (blk: {
        _ = browser.Names(&names);
        break :blk names[0];
    }));

    //the pane's menu
    try std.testing.expect(browser.mPanel.ActionOf(browser.mPanel.mNewScene, 1).? == .NewScene);
}

test "the Scripts panel takes an entity script onto an entity and a scene script onto a scene, and nothing else" {
    try std.testing.expectEqual(.entity, ScriptsPanel.ScriptOwnerOf(.EntityOnUpdate).?);
    try std.testing.expectEqual(.scene_layer, ScriptsPanel.ScriptOwnerOf(.SceneOnUpdate).?);

    //a texture dropped on it: left alone, nothing loaded
    const browser = try TestBrowser.Init();
    defer browser.Deinit();
    const engine_context = browser.mEngineContext;
    const page = try browser.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try page.AddComponent(engine_context, LayoutComponent{ .mDirection = .Column });
    var scripts = try ScriptsPanel.Build(engine_context, page, .{ .StockScripts = false });
    defer scripts.Deinit(engine_context.EngineAllocator());
    const entity = try browser.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
    const texture = try browser.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try texture.AddComponent(engine_context, try FileRefComponent.Init(engine_context, "hero.png", .Prj));

    try scripts.OnDrop(engine_context, .{ .mEntity = scripts.mArea, .mSource = texture, .mPosition = .{ .x = 0, .y = 0, .z = 0 } }, .{ .entity = entity });
    var children = entity.GetIterator(.Script);
    try std.testing.expect(children.next() == null);
}
