//! The Asset Handles panel (EditorPanels/AssetHandlesPanel.zig) and the column of lines it keeps showing its list
//! (Widgets.Lines and SyncLines): lines made and deleted only as the list grows and shrinks, and their text only set
//! when it changes. No window or asset manager needed. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const Widgets = @import("../../UI/Widgets.zig");
const AssetHandlesPanel = @import("../../EditorPanels/AssetHandlesPanel.zig");

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
        try engine_context.mUIManager.Init(engine_context.EngineAllocator());
        try engine_context.mEditorWorld.Init(engine_context.EngineAllocator());
        self.mScene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
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

    const panel = try AssetHandlesPanel.Build(engine_context, world.mScene, .{ .StockScripts = false });
    try std.testing.expect(!panel.IsOpen());
    //closed, it doesn't look at the asset manager at all
    try panel.Update(engine_context);
    try panel.Toggle(engine_context);
    try std.testing.expect(panel.IsOpen());
    try panel.Toggle(engine_context);
    try std.testing.expect(!panel.IsOpen());
}
