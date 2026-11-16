//! The Profiler panel in the editor's own UI (EditorPanels/ProfilerPanel.zig): a floating window, closed to start with,
//! with a row per profiler node under its parent's row, numbers on the rows that can be seen, and nodes met later added
//! as they come. Measures into a profiler of its own, not the engine's. No window or renderer needed. Run with
//! `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const Profiler = @import("../../Core/Profiler.zig");
const ProfilerPanel = @import("../../EditorPanels/ProfilerPanel.zig");
const TextComponent = @import("../../ECSComponents/EComponents.zig").TextComponent;
const GPUAllocator = @import("../../Core/GPUAllocator.zig");
const EditorShell = @import("../../Programs/EditorShell.zig");
const SelectedTag = @import("../../ECSComponents/EComponents.zig").SelectedTag;

fn TextOf(label: Entity) []const u8 {
    return label.GetComponent(TextComponent).?.mText.items;
}

test "the profiler window shows a row per node under its parent's, with numbers on the rows that can be seen" {
    const engine_context = try std.heap.page_allocator.create(EngineContext);
    defer std.heap.page_allocator.destroy(engine_context);
    engine_context.* = .{};
    try engine_context.mUIManager.Init(engine_context);
    try engine_context.mEditorWorld.Init(engine_context);
    var panel: ProfilerPanel = .{};
    defer {
        panel.Deinit(engine_context.mEditorWorld.Keep());
        engine_context.mGPUAllocator.mGroups.deinit(engine_context.Keep());
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        _ = engine_context._Internal.KeepHeap.deinit();
    }
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);

    var profiler: Profiler = .{};
    panel = try ProfilerPanel.Build(engine_context, scene, .Editor, .{ .StockScripts = false });
    try std.testing.expect(!panel.IsOpen());
    try panel.Toggle(engine_context);

    //not running: it says so, and has no tree
    try panel.Update(engine_context, &profiler);
    try std.testing.expectEqualStrings("Not measuring", TextOf(panel.mNote));
    try std.testing.expect(panel.mTree == null);
    //the memory tree shows all the same: the engine's node at the top here (no Application), the editor world under it
    try std.testing.expect(panel.mMemoryTree != null);
    try std.testing.expect(std.mem.startsWith(u8, TextOf(panel.mMemoryRows.items[0].Title), "Engine   "));
    var editor_row: ?usize = null;
    for (panel.mMemoryRows.items, 0..) |row, row_ind| {
        if (row.Node == &engine_context.mEditorWorld.mMemory) editor_row = row_ind;
    }
    try std.testing.expectEqual(@as(?usize, 0), panel.mMemoryRows.items[editor_row.?].Parent);
    try std.testing.expect(std.mem.startsWith(u8, TextOf(panel.mMemoryRows.items[editor_row.?].Title), "Editor   "));
    //every row's own count is at or above nothing: what is taken through a node is freed through it (styles included)
    for (panel.mMemoryRows.items) |row| {
        const own = row.Node.mCounts.Read();
        if (own.KeepBytes < 0) std.debug.print("{s} holds {d} bytes\n", .{ row.Node.mName, own.KeepBytes });
        try std.testing.expect(own.KeepBytes >= 0);
    }

    //the video memory tree: everything, what the engine made, and what it didn't, then the texture atlas's use, a row
    //for each size of texture
    try std.testing.expectEqual(@as(usize, 11), panel.mVideoRows.items.len);
    try std.testing.expect(std.mem.startsWith(u8, TextOf(panel.mVideoRows.items[0].Title), "Video memory   "));
    try std.testing.expect(std.mem.startsWith(u8, TextOf(panel.mVideoRows.items[1].Title), "Made by the engine   "));
    try std.testing.expect(std.mem.startsWith(u8, TextOf(panel.mVideoRows.items[2].Title), "Not made by the engine"));
    //no atlas made here: none of it in use
    try std.testing.expectEqualStrings("Texture atlas in use   0 B of 0 B in slots holding a texture   0 of 0 layers claimed (0 B)", TextOf(panel.mVideoRows.items[3].Title));
    try std.testing.expectEqualStrings("Up to 60 px   0 B in 0 of 0 slots   0 layers", TextOf(panel.mVideoRows.items[4].Title));
    //a group met since gets its owner's row and its own under what the engine made, on the next refresh
    try engine_context.mGPUAllocator.mGroups.append(engine_context.Keep(), .{ .Owner = GPUAllocator.ENGINE, .Name = "Texture atlas", .Kind = .Texture, .Bytes = 2048, .Peak = 4096, .Count = 1 });
    engine_context.mDT = ProfilerPanel.REFRESH_SECONDS;
    try panel.Update(engine_context, &profiler);
    try std.testing.expectEqual(@as(usize, 13), panel.mVideoRows.items.len);
    try std.testing.expect(std.mem.startsWith(u8, TextOf(panel.mVideoRows.items[2].Title), "Engine (shared)   "));
    try std.testing.expectEqualStrings("Texture atlas   2.0 KB   peak 4.0 KB   texture x1", TextOf(panel.mVideoRows.items[3].Title));

    try profiler.Start(engine_context.Keep(), std.testing.io);
    defer profiler.Stop();
    var loop: Profiler.Site = .{ .mName = "Loop" };
    var inner: Profiler.Site = .{ .mName = "Inner" };
    _ = profiler.Begin(&loop);
    _ = profiler.Begin(&inner);
    profiler.End();
    profiler.End();
    profiler.EndLoop();

    engine_context.mDT = ProfilerPanel.REFRESH_SECONDS;
    try panel.Update(engine_context, &profiler);
    try std.testing.expect(std.mem.startsWith(u8, TextOf(panel.mNote), "A pass of the loop, over the last 1:"));
    //the root's row and one for each node
    try std.testing.expectEqual(@as(usize, 3), panel.mRows.items.len);
    //the top node starts open, so its row and the one under it both have numbers; called once a pass
    try std.testing.expect(std.mem.startsWith(u8, TextOf(panel.mRows.items[1].Title), "Loop   "));
    try std.testing.expect(std.mem.endsWith(u8, TextOf(panel.mRows.items[1].Title), "x1.0"));
    try std.testing.expect(std.mem.startsWith(u8, TextOf(panel.mRows.items[2].Title), "Inner   "));

    //a node met later gets its row on the next refresh, under its parent's
    var later: Profiler.Site = .{ .mName = "Later" };
    _ = profiler.Begin(&loop);
    _ = profiler.Begin(&inner);
    _ = profiler.Begin(&later);
    profiler.End();
    profiler.End();
    profiler.End();
    profiler.EndLoop();
    try panel.Update(engine_context, &profiler);
    try std.testing.expectEqual(@as(usize, 4), panel.mRows.items.len);
    //Inner starts folded, so the row under it is left as it was made
    try std.testing.expectEqualStrings("Later", TextOf(panel.mRows.items[3].Title));

    //a zone run on a world has the world's name in front, and the line above the tree adds up its time
    var run: Profiler.Site = .{ .mName = "Run" };
    _ = profiler.Begin(&loop);
    const outer = profiler.EnterWorld(engine_context.WorldTag(&engine_context.mGameWorld));
    _ = profiler.Begin(&run);
    profiler.End();
    profiler.LeaveWorld(outer);
    profiler.End();
    profiler.EndLoop();
    try panel.Update(engine_context, &profiler);
    try std.testing.expect(std.mem.startsWith(u8, TextOf(panel.mRows.items[4].Title), "[Game] Run   "));
    try std.testing.expect(std.mem.startsWith(u8, TextOf(panel.mWorlds), "Each world, a pass on average: Game "));
}

test "above the sections, frames and passes of the loop a second; then each world's last rendered frame, the editor's three or a game's one" {
    const engine_context = try std.heap.page_allocator.create(EngineContext);
    defer std.heap.page_allocator.destroy(engine_context);
    engine_context.* = .{};
    try engine_context.mUIManager.Init(engine_context);
    try engine_context.mEditorWorld.Init(engine_context);
    var panel: ProfilerPanel = .{};
    var game_panel: ProfilerPanel = .{};
    defer {
        panel.Deinit(engine_context.mEditorWorld.Keep());
        game_panel.Deinit(engine_context.mEditorWorld.Keep());
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        _ = engine_context._Internal.KeepHeap.deinit();
    }
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    panel = try ProfilerPanel.Build(engine_context, scene, .Editor, .{ .StockScripts = false });
    try panel.Toggle(engine_context);

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
    engine_context.mDT = ProfilerPanel.REFRESH_SECONDS;
    var profiler: Profiler = .{};
    try panel.Update(engine_context, &profiler);
    try std.testing.expectEqualStrings("32 FPS   64 passes of the loop a second", TextOf(panel.mRates));
    //the last rendered frame's, kept when the frame's were reset
    const editor = panel.mEditor.?;
    try std.testing.expectEqualStrings("Glyphs: 42", TextOf(editor.Glyphs));
    //each layer's BVH: its deepest and average leaf, then its size; a layer with no tree is all 0. Then both trees' costs
    try std.testing.expectEqualStrings("Overlay BVH: depth 3 (avg 2.5), 7 nodes, 4 leaves of 3.5", TextOf(editor.OverlayBVH));
    try std.testing.expectEqualStrings("Game BVH: depth 0 (avg 0.0), 0 nodes, 0 leaves of 0.0", TextOf(editor.GameBVH));
    try std.testing.expectEqualStrings("BVH cost: overlay 6.5, game 0.0", TextOf(editor.BVHCosts));
    try std.testing.expectEqual(@as(usize, 0), engine_context.mEngineStats.EditorWorldStats.mRenderStats.OutputGlyphNum);
    //every world's section starts folded
    try std.testing.expect(!EditorShell.IsShown(panel.mGame.Objects));
    try std.testing.expect(!EditorShell.IsShown(editor.Glyphs));
    try std.testing.expect(EditorShell.IsShown(panel.mRates));

    //a game's has only the Game world's
    game_panel = try ProfilerPanel.Build(engine_context, scene, .Game, .{ .StockScripts = false });
    try std.testing.expect(game_panel.mEditor == null);
    try std.testing.expect(game_panel.mSimulate == null);
}

test "ticking Measure turns conflict measuring on from fresh counts, and the section shows what it found" {
    const engine_context = try std.heap.page_allocator.create(EngineContext);
    defer std.heap.page_allocator.destroy(engine_context);
    engine_context.* = .{};
    try engine_context.mUIManager.Init(engine_context);
    try engine_context.mEditorWorld.Init(engine_context);
    var panel: ProfilerPanel = .{};
    defer {
        panel.Deinit(engine_context.mEditorWorld.Keep());
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        _ = engine_context._Internal.KeepHeap.deinit();
    }
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    const conflicts = &engine_context.mTransactions.mConflicts;
    var profiler: Profiler = .{};

    panel = try ProfilerPanel.Build(engine_context, scene, .Editor, .{ .StockScripts = false });
    try panel.Toggle(engine_context);
    try panel.Update(engine_context, &profiler);
    try std.testing.expect(!conflicts.mOn);
    try std.testing.expectEqualStrings("Not measuring", TextOf(panel.mConflictTotal));

    //what the stock Toggle script does when the box is clicked
    _ = try panel.mMeasureBox.AddComponent(engine_context, SelectedTag{});
    try panel.Update(engine_context, &profiler);
    try std.testing.expect(conflicts.mOn);

    //a batch found by measuring: 4 hooks of a loop, 1 of which would conflict, on a transform
    {
        const allocator = engine_context.Keep();
        const entry = try conflicts.mSystems.getOrPut(allocator, "ScriptsProcessor::RunScript(Entity, OnUpdateScript, Game)");
        entry.key_ptr.* = try allocator.dupe(u8, entry.key_ptr.*);
        entry.value_ptr.* = .{ .mBatches = 2, .mHooks = 4, .mConflicts = 1 };
        try entry.value_ptr.mTypes.put(allocator, try allocator.dupe(u8, "ECSComponents.Shared.TransformComponent"), 1);
    }
    engine_context.mDT = ProfilerPanel.REFRESH_SECONDS;
    try panel.Update(engine_context, &profiler);
    try std.testing.expectEqualStrings("1 of 4 hooks would conflict (25.0%), 0 would run on their own", TextOf(panel.mConflictTotal));
    try std.testing.expectEqualStrings("RunScript(Entity, OnUpdateScript, Game): 1 of 4 would conflict, 0 on their own, 2 runs, mostly on TransformComponent", TextOf(panel.mConflictLines[0]));

    try panel.mMeasureBox.RemoveComponentSync(engine_context, SelectedTag);
    try panel.Update(engine_context, &profiler);
    try std.testing.expect(!conflicts.mOn);
}
