//! The Stats panel in the editor's own UI (EditorPanels/StatsPanel.zig): a floating window, closed to start with, whose
//! world sections start folded, and whose lines show the loop's time, loops and frames a second, and the last
//! rendered frame's stats. No window or
//! renderer needed. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const StatsPanel = @import("../../EditorPanels/StatsPanel.zig");
const EditorShell = @import("../../Programs/EditorShell.zig");
const UIManager = @import("../../UI/UIManager.zig");
const UIComponents = @import("../../ECSComponents/UIComponents.zig");
const TextComponent = @import("../../ECSComponents/EComponents.zig").TextComponent;

fn TextOf(label: Entity) []const u8 {
    return label.GetComponent(TextComponent).?.mText.items;
}

test "the stats window starts closed, opens and closes, and shows the loop, the frame rate and the last rendered frame's world stats" {
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

    const panel = try StatsPanel.Build(engine_context, scene, .{ .StockScripts = false });
    try std.testing.expect(!panel.IsOpen());
    //closed, it shows nothing new
    engine_context.mDT = 0.02;
    try panel.Update(engine_context, &engine_context.mEngineStats);
    try std.testing.expectEqualStrings("", TextOf(panel.mFPS));

    try panel.Toggle(engine_context);
    try std.testing.expect(panel.IsOpen());
    //a second of 64 passes of the loop (a power of two, which adds up to exactly a second), half of them drawn, the
    //last of which drew 42 glyphs
    engine_context.mDT = 1.0 / 64.0;
    for (0..64) |i| {
        if (i % 2 == 1) engine_context.mEngineStats.FrameAcquired();
        engine_context.mEngineStats.EditorWorldStats.mRenderStats.OutputGlyphNum = 42;
        engine_context.mEngineStats.ResetStats();
        engine_context.mEngineStats.CountLoop(engine_context.mDT);
    }
    try panel.Update(engine_context, &engine_context.mEngineStats);
    try std.testing.expectEqualStrings("FPS: 32", TextOf(panel.mFPS));
    try std.testing.expectEqualStrings("Loops/s: 64", TextOf(panel.mLoopRate));
    try std.testing.expectEqualStrings("Loop time: 15625 us (0.01563 s)", TextOf(panel.mLoopTime));
    //the last rendered frame's, kept when the frame's were reset
    try std.testing.expectEqualStrings("Glyphs: 42", TextOf(panel.mEditor.Glyphs));
    try std.testing.expectEqual(@as(usize, 0), engine_context.mEngineStats.EditorWorldStats.mRenderStats.OutputGlyphNum);

    //every world's section starts folded
    try std.testing.expect(!EditorShell.IsShown(panel.mGame.Objects));
    try std.testing.expect(!EditorShell.IsShown(panel.mEditor.Glyphs));
    try std.testing.expect(EditorShell.IsShown(panel.mFPS));

    //what runs past the window scrolls
    const content = panel.mFPS.GetComponent(@import("../../ECS/Components.zig").ChildComponent(Entity.Type)).?.mParent;
    try std.testing.expect(UIManager.HasUIComponent(engine_context.mEditorWorld.GetEntity(content), UIComponents.ScrollComponent));

    try panel.Toggle(engine_context);
    try std.testing.expect(!panel.IsOpen());
}
