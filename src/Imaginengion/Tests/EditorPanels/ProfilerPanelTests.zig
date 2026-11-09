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
        panel.Deinit(engine_context.EngineAllocator());
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
    }
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);

    var profiler: Profiler = .{};
    panel = try ProfilerPanel.Build(engine_context, scene, .{ .StockScripts = false });
    try std.testing.expect(!panel.IsOpen());
    try panel.Toggle(engine_context);

    //not running: it says so, and has no tree
    try panel.Update(engine_context, &profiler);
    try std.testing.expectEqualStrings("Not measuring", TextOf(panel.mNote));
    try std.testing.expect(panel.mTree == null);

    try profiler.Start(engine_context.EngineAllocator(), std.testing.io);
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
}
