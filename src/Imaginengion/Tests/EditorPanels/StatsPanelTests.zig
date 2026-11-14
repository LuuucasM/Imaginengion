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
const SelectedTag = @import("../../ECSComponents/EComponents.zig").SelectedTag;

fn TextOf(label: Entity) []const u8 {
    return label.GetComponent(TextComponent).?.mText.items;
}

test "the stats window starts closed, opens and closes, and shows the loop, the frame rate and the last rendered frame's world stats" {
    const engine_context = try std.heap.page_allocator.create(EngineContext);
    defer std.heap.page_allocator.destroy(engine_context);
    engine_context.* = .{};
    try engine_context.mUIManager.Init(engine_context);
    try engine_context.mEditorWorld.Init(engine_context);
    defer {
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        _ = engine_context._Internal.KeepHeap.deinit();
    }
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);

    var panel = try StatsPanel.Build(engine_context, scene, .{ .StockScripts = false });
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
        engine_context.mEngineStats.EditorWorldStats.mRenderStats.OverlayBVH = .{ .Nodes = 7, .Leaves = 4, .Depth = 3, .LeafDepths = 10, .Items = 14, .Cost = 6.5 };
        engine_context.mEngineStats.ResetStats();
        engine_context.mEngineStats.CountLoop(engine_context.mDT);
    }
    try panel.Update(engine_context, &engine_context.mEngineStats);
    try std.testing.expectEqualStrings("FPS: 32", TextOf(panel.mFPS));
    try std.testing.expectEqualStrings("Loops/s: 64", TextOf(panel.mLoopRate));
    try std.testing.expectEqualStrings("Loop time: 15625 us (0.01563 s)", TextOf(panel.mLoopTime));
    //a memory line for each owner, the game world's first
    try std.testing.expect(std.mem.startsWith(u8, TextOf(panel.mMemoryLines[0]), "Game: Keep "));
    try std.testing.expect(std.mem.startsWith(u8, TextOf(panel.mMemoryLines[@intFromEnum(StatsPanel.MemoryOwner.Engine)]), "Engine (shared): Keep "));
    try std.testing.expect(std.mem.endsWith(u8, TextOf(panel.mMemoryLines[0]), "GPU 0 B / 0 B in 0 textures, 0 buffers"));
    //the last rendered frame's, kept when the frame's were reset
    try std.testing.expectEqualStrings("Glyphs: 42", TextOf(panel.mEditor.Glyphs));
    //each layer's BVH: its deepest and average leaf, then its size; a layer with no tree is all 0. Then both trees' costs
    try std.testing.expectEqualStrings("Overlay BVH: depth 3 (avg 2.5), 7 nodes, 4 leaves of 3.5", TextOf(panel.mEditor.OverlayBVH));
    try std.testing.expectEqualStrings("Game BVH: depth 0 (avg 0.0), 0 nodes, 0 leaves of 0.0", TextOf(panel.mEditor.GameBVH));
    try std.testing.expectEqualStrings("BVH cost: overlay 6.5, game 0.0", TextOf(panel.mEditor.BVHCosts));
    try std.testing.expectEqual(@as(usize, 0), engine_context.mEngineStats.EditorWorldStats.mRenderStats.OutputGlyphNum);

    //every world's section starts folded
    try std.testing.expect(!EditorShell.IsShown(panel.mGame.Objects));
    try std.testing.expect(!EditorShell.IsShown(panel.mEditor.Glyphs));
    try std.testing.expect(EditorShell.IsShown(panel.mFPS));

    //what runs past the window scrolls
    const content = panel.mFPS.GetComponent(@import("../../ECS/Components.zig").ChildComponent(Entity.Type)).?.mParent;
    try std.testing.expect(UIManager.HasUIComponent(engine_context.mEditorWorld.GetEntity(content), UIComponents.ScrollComponent));

    //its lines only change every so often, however often the loop goes round
    engine_context.mDT = StatsPanel.REFRESH_SECONDS / 4;
    try panel.Update(engine_context, &engine_context.mEngineStats);
    try std.testing.expectEqualStrings("Loop time: 15625 us (0.01563 s)", TextOf(panel.mLoopTime));
    engine_context.mDT = StatsPanel.REFRESH_SECONDS;
    try panel.Update(engine_context, &engine_context.mEngineStats);
    try std.testing.expect(!std.mem.eql(u8, "Loop time: 15625 us (0.01563 s)", TextOf(panel.mLoopTime)));

    try panel.Toggle(engine_context);
    try std.testing.expect(!panel.IsOpen());

    //closed for a moment, it shows the latest as soon as it opens again
    engine_context.mDT = 0;
    try panel.Update(engine_context, &engine_context.mEngineStats);
    try panel.Toggle(engine_context);
    const shown_before = try engine_context.Scratch().dupe(u8, TextOf(panel.mLoopTime));
    try panel.Update(engine_context, &engine_context.mEngineStats);
    try std.testing.expect(!std.mem.eql(u8, shown_before, TextOf(panel.mLoopTime)));
}

test "ticking Measure turns conflict measuring on from fresh counts, and the section shows what it found" {
    const engine_context = try std.heap.page_allocator.create(EngineContext);
    defer std.heap.page_allocator.destroy(engine_context);
    engine_context.* = .{};
    try engine_context.mUIManager.Init(engine_context);
    try engine_context.mEditorWorld.Init(engine_context);
    defer {
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        _ = engine_context._Internal.KeepHeap.deinit();
    }
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    const conflicts = &engine_context.mTransactions.mConflicts;

    var panel = try StatsPanel.Build(engine_context, scene, .{ .StockScripts = false });
    try panel.Toggle(engine_context);
    try panel.Update(engine_context, &engine_context.mEngineStats);
    try std.testing.expect(!conflicts.mOn);
    try std.testing.expectEqualStrings("Not measuring", TextOf(panel.mConflictTotal));

    //what the stock Toggle script does when the box is clicked
    _ = try panel.mMeasureBox.AddComponent(engine_context, SelectedTag{});
    try panel.Update(engine_context, &engine_context.mEngineStats);
    try std.testing.expect(conflicts.mOn);

    //a batch found by measuring: 4 hooks of a loop, 1 of which would conflict, on a transform
    {
        const allocator = engine_context.Keep();
        const entry = try conflicts.mSystems.getOrPut(allocator, "ScriptsProcessor::RunScript(Entity, OnUpdateScript, Game)");
        entry.key_ptr.* = try allocator.dupe(u8, entry.key_ptr.*);
        entry.value_ptr.* = .{ .mBatches = 2, .mHooks = 4, .mConflicts = 1 };
        try entry.value_ptr.mTypes.put(allocator, try allocator.dupe(u8, "ECSComponents.Shared.TransformComponent"), 1);
    }
    engine_context.mDT = StatsPanel.REFRESH_SECONDS;
    try panel.Update(engine_context, &engine_context.mEngineStats);
    try std.testing.expectEqualStrings("1 of 4 hooks would conflict (25.0%), 0 would run on their own", TextOf(panel.mConflictTotal));
    try std.testing.expectEqualStrings("RunScript(Entity, OnUpdateScript, Game): 1 of 4 would conflict, 0 on their own, 2 runs, mostly on TransformComponent", TextOf(panel.mConflictLines[0]));

    try panel.mMeasureBox.RemoveComponentSync(engine_context, SelectedTag);
    try panel.Update(engine_context, &engine_context.mEngineStats);
    try std.testing.expect(!conflicts.mOn);
}
