//! The Picking Debug panel in the editor's own UI (EditorPanels/PickingDebugPanel.zig): a floating window, closed to
//! start with, whose sections start folded and are only worked out while open, the pointer section's lines, and the
//! last event kept to show. The view sections need a running editor (EditorProgram.ViewUnder), so they are left folded
//! here. No window or renderer needed. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const PickingDebugPanel = @import("../../EditorPanels/PickingDebugPanel.zig");
const EditorProgram = @import("../../Programs/EditorProgram.zig");
const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const TextComponent = EntityComponents.TextComponent;
const LayoutItemComponent = EntityComponents.LayoutItemComponent;

fn LinesOf(section: PickingDebugPanel.Section, out: [][]const u8) usize {
    var count: usize = 0;
    var children = section.Lines.GetIterator(.Child);
    while (children.next()) |line| : (count += 1) {
        if (count < out.len) out[count] = line.GetComponent(TextComponent).?.mText.items;
    }
    return count;
}

fn Unfold(section: PickingDebugPanel.Section) void {
    section.Content.GetComponent(LayoutItemComponent).?.mCollapsed = false;
}

test "sections start folded and are only filled in while open, and the pointer section shows the last event" {
    const engine_context = try std.heap.page_allocator.create(EngineContext);
    defer std.heap.page_allocator.destroy(engine_context);
    engine_context.* = .{};
    try engine_context.mUIManager.Init(engine_context.EngineAllocator());
    try engine_context.mEditorWorld.Init(engine_context.EngineAllocator());
    defer {
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
    }
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    const editor_program = try std.heap.page_allocator.create(EditorProgram);
    defer std.heap.page_allocator.destroy(editor_program);
    editor_program.* = .{};

    var panel = try PickingDebugPanel.Build(engine_context, scene, .{ .StockScripts = false });
    try std.testing.expect(!panel.IsOpen());
    var lines: [16][]const u8 = undefined;

    //closed: nothing filled in
    try panel.Update(engine_context, editor_program);
    try std.testing.expectEqual(@as(usize, 0), LinesOf(panel.mPointer, &lines));

    //open, but every section folded: still nothing
    try panel.Toggle(engine_context);
    try panel.Update(engine_context, editor_program);
    try std.testing.expectEqual(@as(usize, 0), LinesOf(panel.mPointer, &lines));
    try std.testing.expectEqual(@as(usize, 0), LinesOf(panel.mWindowSection, &lines));

    //the pointer section unfolded: its lines, with the last event once there is one
    Unfold(panel.mPointer);
    try panel.Update(engine_context, editor_program);
    try std.testing.expectEqual(@as(usize, 8), LinesOf(panel.mPointer, &lines));
    try std.testing.expectEqualStrings("Pointing into: nothing yet", lines[0]);
    try std.testing.expectEqualStrings("Pointer over: nothing", lines[2]);
    try std.testing.expectEqualStrings("Last event: none yet", lines[7]);

    const button = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    try button.SetName(engine_context, "Button");
    panel.OnPointerEvent(.{ .mEntity = button, .mEvent = .{ .PointerClicked = .{ .mButton = .BUTTON_LEFT, .mClicks = 2, .mPosition = .{ .x = 0, .y = 0, .z = 0 }, .mTarget = button } } });
    try panel.Update(engine_context, editor_program);
    _ = LinesOf(panel.mPointer, &lines);
    try std.testing.expectEqualStrings("Last event: BUTTON_LEFT clicked 'Button' x2", lines[7]);

    //the window section, unfolded
    Unfold(panel.mWindowSection);
    try panel.Update(engine_context, editor_program);
    try std.testing.expectEqual(@as(usize, 3), LinesOf(panel.mWindowSection, &lines));
    try std.testing.expectEqualStrings("Views drawn: Viewport 0, Play 0", lines[2]);

    try panel.Toggle(engine_context);
    try std.testing.expect(!panel.IsOpen());
}
