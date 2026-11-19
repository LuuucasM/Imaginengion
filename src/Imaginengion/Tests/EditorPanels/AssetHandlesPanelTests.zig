//! The Asset Handles panel (EditorPanels/AssetHandlesPanel.zig): a section per asset type, a row per asset with what it
//! takes and whether it is on its way out. And the column of lines widget (Widgets.Lines and SyncLines): lines made and
//! deleted only as the list grows and shrinks, and their text only set when it changes. No window or GPU needed. Run
//! with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const Widgets = @import("../../UI/Widgets.zig");
const AssetHandlesPanel = @import("../../EditorPanels/AssetHandlesPanel.zig");
const EngineFiles = @import("../../GameBuild/EngineFiles.zig");
const Assets = @import("../../ECSComponents/AComponents.zig");

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const TextComponent = EntityComponents.TextComponent;
const LayoutDirtyTag = EntityComponents.LayoutDirtyTag;

const SEventData = @import("../../Events/SManagerData.zig");
const EEventData = @import("../../Events/EManagerData.zig");
const ECSEventData = @import("../../Events/ECSEventData.zig");

const TestWorld = struct {
    mEngineContext: *EngineContext,
    mScene: Scene = undefined,

    fn Init() !*TestWorld {
        const self = try std.heap.page_allocator.create(TestWorld);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        try engine_context.mUIManager.Init(engine_context);
        try engine_context.mEditorWorld.Init(engine_context);
        self.mScene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        _ = engine_context._Internal.KeepHeap.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    /// EditorProgram.OnUpdate's end of frame for the editor world, where deletes happen
    fn EndFrame(self: *TestWorld) !void {
        const engine_context = self.mEngineContext;
        const world = &engine_context.mEditorWorld;
        var callback_list: std.DoublyLinkedList = .{};
        try world.ProcessEvents(SEventData, .EndOfFrame, engine_context, &callback_list);
        try world.ProcessEvents(EEventData, .EndOfFrame, engine_context, &callback_list);
        try world.ProcessEvents(ECSEventData, .EndOfFrame, engine_context, &callback_list);
    }
};

/// The column's lines' text, in order
fn LinesOf(column: Entity) ![]const []const u8 {
    var lines: std.ArrayList([]const u8) = .empty;
    var children = column.GetIterator(.Child);
    while (children.next()) |child| try lines.append(std.testing.allocator, child.GetComponent(TextComponent).?.mText.items);
    return lines.toOwnedSlice(std.testing.allocator);
}

fn ExpectLines(expected: []const []const u8, column: Entity) !void {
    const actual = try LinesOf(column);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |e, a| try std.testing.expectEqualStrings(e, a);
}

test "a column of lines follows its list as it grows, changes and shrinks, and a line that already says it is left alone" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const panel = try world.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
    const column = try Widgets.Lines(engine_context, .{ .Entity = panel });

    try Widgets.SyncLines(engine_context, column, &.{ "1: a.png", "2: b.ttf" });
    try ExpectLines(&.{ "1: a.png", "2: b.ttf" }, column);

    //the same list: no line is set again, so nothing has to be laid out
    var children = column.GetIterator(.Child);
    const first = children.next().?;
    if (first.HasComponent(LayoutDirtyTag)) try first.RemoveComponentSync(engine_context, LayoutDirtyTag);
    try Widgets.SyncLines(engine_context, column, &.{ "1: a.png", "2: b.ttf" });
    try std.testing.expect(!first.HasComponent(LayoutDirtyTag));

    try Widgets.SyncLines(engine_context, column, &.{ "1: a.png", "3: c.wav", "4: d.imsc" });
    try ExpectLines(&.{ "1: a.png", "3: c.wav", "4: d.imsc" }, column);
    var after = column.GetIterator(.Child);
    try std.testing.expectEqual(first.mID, after.next().?.mID);

    try Widgets.SyncLines(engine_context, column, &.{"4: d.imsc"});
    try world.EndFrame();
    try ExpectLines(&.{"4: d.imsc"}, column);
}

test "the asset handles window starts closed, and opens and closes" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    var panel = try AssetHandlesPanel.Build(engine_context, world.mScene, .{ .StockScripts = false });
    defer panel.Deinit(engine_context.ProgramKeep());
    try std.testing.expect(!panel.IsOpen());
    //closed, it doesn't look at the asset manager at all
    try panel.Update(engine_context);
    try panel.Toggle(engine_context);
    try std.testing.expect(panel.IsOpen());
    try panel.Toggle(engine_context);
    try std.testing.expect(!panel.IsOpen());
}

fn TextOf(label: Entity) []const u8 {
    return label.GetComponent(TextComponent).?.mText.items;
}

test "each asset is under its type's section with what it takes, and one on its way out says so" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const asset_manager = &engine_context.mAssetManager;
    engine_context._Internal.ThreadPool = std.Io.Threaded.init(engine_context._Internal.KeepHeap.allocator(), .{ .concurrent_limit = .nothing, .async_limit = .nothing });
    try asset_manager.Init(engine_context);
    defer {
        const keep_allocator = engine_context.Keep();
        asset_manager.mECSManager.Deinit(engine_context);
        asset_manager.mUUIDToWorldID.deinit(keep_allocator);
        asset_manager.mEventManager.Deinit(keep_allocator);
        asset_manager.mCWDPath.deinit(keep_allocator);
    }

    //a sound read in (the one asset that needs no GPU), and a script named but not read in yet
    var sound = try asset_manager.GetAssetHandle(engine_context, .{ .File = .{ .rel_path = EngineFiles.DEFAULT_SOUND, .path_type = .Eng } });
    _ = try sound.GetAsset(engine_context, Assets.AudioAsset);
    var script = try asset_manager.GetAssetHandle(engine_context, .{ .File = .{ .rel_path = "src/Imaginengion/EngineAssets/scripts/UI/Toggle.zig", .path_type = .Eng } });
    defer script.ReleaseAsset();

    var panel = try AssetHandlesPanel.Build(engine_context, world.mScene, .{ .StockScripts = false });
    defer panel.Deinit(engine_context.ProgramKeep());
    try panel.Toggle(engine_context);
    engine_context.mDT = AssetHandlesPanel.REFRESH_SECONDS;
    try panel.Update(engine_context);

    try std.testing.expectEqual(@as(usize, 2), panel.mRows.items.len);
    const sounds = panel.mSections[@intFromEnum(AssetHandlesPanel.Category.Sounds)].?;
    try std.testing.expect(std.mem.startsWith(u8, TextOf(sounds), "Sounds   1   "));
    try std.testing.expect(std.mem.endsWith(u8, TextOf(sounds), " decoded"));
    const sound_row = TextOf(panel.mRows.items[0].Title);
    try std.testing.expect(std.mem.startsWith(u8, sound_row, EngineFiles.DEFAULT_SOUND ++ "   held by 1   "));
    try std.testing.expect(std.mem.endsWith(u8, sound_row, " decoded"));
    try std.testing.expectEqualStrings("Not loaded   1", TextOf(panel.mSections[@intFromEnum(AssetHandlesPanel.Category.NotLoaded)].?));
    try std.testing.expect(panel.mSections[@intFromEnum(AssetHandlesPanel.Category.Textures)] == null);

    //let go of: unused, and going once the grace period is over
    sound.ReleaseAsset();
    try asset_manager.ProcessDestroyedAssets(engine_context);
    try panel.Update(engine_context);
    try std.testing.expect(std.mem.indexOf(u8, TextOf(panel.mRows.items[0].Title), "held by 0   unused, goes in ") != null);
}
