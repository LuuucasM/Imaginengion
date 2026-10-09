//! The Scripts panel in the editor's own UI (EditorPanels/ScriptsPanel.zig): the lines saying what is selected and why
//! there is nothing to list, a row per script, built again when the selection or its scripts change, Delete through a
//! row's menu, and hiding it from the Window menu. Script children are made directly, since adding a real script
//! compiles it. No window needed. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const Player = @import("../../ECSObjects/Player.zig");
const ScriptsPanel = @import("../../EditorPanels/ScriptsPanel.zig");
const SelectedObject = @import("../../Programs/EditorProgram.zig").SelectedObject;
const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const TextComponent = EntityComponents.TextComponent;
const LayoutComponent = EntityComponents.LayoutComponent;
const LayoutItemComponent = EntityComponents.LayoutItemComponent;

const TestPanel = struct {
    mEngineContext: *EngineContext,
    mScene: Scene = undefined,
    mPanel: ScriptsPanel = .{},

    fn Init() !*TestPanel {
        const self = try std.heap.page_allocator.create(TestPanel);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        try engine_context.mUIManager.Init(engine_context.EngineAllocator());
        try engine_context.mEditorWorld.Init(engine_context.EngineAllocator());
        self.mScene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
        //the shell's tab page
        const page = try self.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
        _ = try page.AddComponent(engine_context, LayoutComponent{ .mDirection = .Column });
        self.mPanel = try ScriptsPanel.Build(engine_context, page, .{ .StockScripts = false });
        return self;
    }

    fn Deinit(self: *TestPanel) void {
        const engine_context = self.mEngineContext;
        self.mPanel.Deinit(engine_context.EngineAllocator());
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    /// A script child of `entity`, named `name`, the way AddScript makes one but without a script asset
    fn AddScript(self: *TestPanel, entity: Entity, name: []const u8) !Entity {
        const script = try entity.CreateChild(self.mEngineContext, .Script, Entity.ScriptConfig);
        try script.SetName(self.mEngineContext, name);
        return script;
    }

    fn Update(self: *TestPanel, selected: ?SelectedObject) !void {
        try self.mPanel.Update(self.mEngineContext, selected);
    }

    fn RowNames(self: *TestPanel, out: [][]const u8) usize {
        const rows = self.mPanel.mRows orelse return 0;
        var count: usize = 0;
        var children = rows.GetIterator(.Child);
        while (children.next()) |row| : (count += 1) {
            var parts = row.GetIterator(.Child);
            if (count < out.len) out[count] = parts.next().?.GetComponent(TextComponent).?.mText.items;
        }
        return count;
    }
};

fn TextOf(line: Entity) []const u8 {
    return line.GetComponent(TextComponent).?.mText.items;
}

fn IsFolded(line: Entity) bool {
    return line.GetComponent(LayoutItemComponent).?.mCollapsed;
}

test "the lines say what is selected and why there is nothing to list" {
    const test_panel = try TestPanel.Init();
    defer test_panel.Deinit();
    const engine_context = test_panel.mEngineContext;
    const panel = &test_panel.mPanel;

    try test_panel.Update(null);
    try std.testing.expectEqualStrings("Select an object to see its scripts", TextOf(panel.mMessage));
    try std.testing.expect(IsFolded(panel.mTitle));

    const player = try engine_context.mEditorWorld.CreatePlayer(engine_context, Player.DefaultConfig);
    try player.SetName(engine_context, "One");
    try test_panel.Update(.{ .player = player });
    try std.testing.expectEqualStrings("One", TextOf(panel.mTitle));
    try std.testing.expectEqualStrings("Players can't have scripts yet", TextOf(panel.mMessage));

    const entity = try test_panel.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
    try entity.SetName(engine_context, "Hero");
    try test_panel.Update(.{ .entity = entity });
    try std.testing.expectEqualStrings("Hero", TextOf(panel.mTitle));
    try std.testing.expectEqualStrings("No scripts yet", TextOf(panel.mMessage));

    //with a script, there is nothing to explain
    _ = try test_panel.AddScript(entity, "Mover");
    try test_panel.Update(.{ .entity = entity });
    try std.testing.expect(IsFolded(panel.mMessage));
}

test "a row per script, built again when the scripts or the selection change, and Delete through a row's menu" {
    const test_panel = try TestPanel.Init();
    defer test_panel.Deinit();
    const engine_context = test_panel.mEngineContext;
    const panel = &test_panel.mPanel;
    const entity = try test_panel.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
    const mover = try test_panel.AddScript(entity, "Mover");
    _ = try test_panel.AddScript(entity, "Jumper");
    try test_panel.Update(.{ .entity = entity });

    var names: [8][]const u8 = undefined;
    try std.testing.expectEqual(@as(usize, 2), test_panel.RowNames(&names));
    try std.testing.expectEqualStrings("Mover", names[0]);
    try std.testing.expectEqualStrings("Jumper", names[1]);

    //nothing changed: not built again
    const rows = panel.mRows.?;
    try test_panel.Update(.{ .entity = entity });
    try std.testing.expectEqual(rows.mID, panel.mRows.?.mID);

    //a row's Delete is that script
    try std.testing.expectEqual(@as(usize, 2), panel.mItems.items.len);
    const to_delete = panel.ActionOf(panel.mItems.items[0].Item).?;
    try std.testing.expectEqual(mover.mID, to_delete.entity.mID);
    try std.testing.expect(panel.ActionOf(rows) == null);

    //a third script: built again with it, the old rows hidden until they are deleted
    _ = try test_panel.AddScript(entity, "Spinner");
    try test_panel.Update(.{ .entity = entity });
    try std.testing.expect(panel.mRows.?.mID != rows.mID);
    try std.testing.expect(IsFolded(rows));
    try std.testing.expectEqual(@as(usize, 3), test_panel.RowNames(&names));

    //another entity, with none
    const other = try test_panel.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
    try test_panel.Update(.{ .entity = other });
    try std.testing.expect(panel.mRows == null);
    try std.testing.expectEqual(@as(usize, 0), panel.mItems.items.len);
}

test "the Window menu hides and shows it, and hidden it isn't updated" {
    const test_panel = try TestPanel.Init();
    defer test_panel.Deinit();
    const engine_context = test_panel.mEngineContext;
    const panel = &test_panel.mPanel;
    try std.testing.expect(panel.IsOpen());

    try panel.Toggle(engine_context);
    try std.testing.expect(!panel.IsOpen());
    try test_panel.Update(null);
    try std.testing.expectEqualStrings("", TextOf(panel.mMessage));

    try panel.Toggle(engine_context);
    try test_panel.Update(null);
    try std.testing.expectEqualStrings("Select an object to see its scripts", TextOf(panel.mMessage));
}
