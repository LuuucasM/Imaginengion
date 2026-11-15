//! The stats window of a game built with -Dstats (Programs/GameStats.zig): the Profiler window, shown through the player
//! on screen, its trees filled in, kept over every other overlay, and hidden again by its key or its close button.
//! Measures into a profiler of its own, not the engine's. No window or renderer needed. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Profiler = @import("../../Core/Profiler.zig");
const GameStats = @import("../../Programs/GameStats.zig");
const ProfilerPanel = @import("../../EditorPanels/ProfilerPanel.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const Player = @import("../../ECSObjects/Player.zig");
const WidgetActions = @import("../../UI/WidgetActions.zig");
const TextComponent = @import("../../ECSComponents/EComponents.zig").TextComponent;
const SceneStackPos = @import("../../ECSComponents/SComponents.zig").StackPosComponent;

fn IsOverlayOf(player: Player, scene: Scene) !bool {
    const overlays = try player.GetOverlayScenes(player.mManager.Scratch());
    for (overlays.items) |overlay| {
        if (overlay == scene.mID) return true;
    }
    return false;
}

test "Ctrl+Shift+F12 shows the profiler window over the game, kept over the game's overlays, and hides it again" {
    const engine_context = try std.heap.page_allocator.create(EngineContext);
    defer std.heap.page_allocator.destroy(engine_context);
    engine_context.* = .{};
    try engine_context.mUIManager.Init(engine_context);
    try engine_context.mGameWorld.Init(engine_context);
    var stats: GameStats = .{ .mOptions = .{ .StockScripts = false } };
    defer {
        stats.mPanel.Deinit(engine_context.mGameWorld.Keep());
        engine_context.mGameWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        _ = engine_context._Internal.KeepHeap.deinit();
    }
    const world = &engine_context.mGameWorld;

    //its key: F12 with both Ctrl and Shift held, once a press
    try std.testing.expect(!GameStats.IsToggle(engine_context, .F12, 0));
    engine_context.mInputManager.SetKeyPressed(.LCTRL);
    try std.testing.expect(!GameStats.IsToggle(engine_context, .F12, 0));
    engine_context.mInputManager.SetKeyPressed(.RSHIFT);
    try std.testing.expect(GameStats.IsToggle(engine_context, .F12, 0));
    try std.testing.expect(!GameStats.IsToggle(engine_context, .F12, 1));
    try std.testing.expect(!GameStats.IsToggle(engine_context, .F3, 0));

    var profiler: Profiler = .{};
    try profiler.Start(engine_context.Keep(), std.testing.io);
    defer profiler.Stop();
    var loop: Profiler.Site = .{ .mName = "Loop" };
    var inner: Profiler.Site = .{ .mName = "Inner" };
    _ = profiler.Begin(&loop);
    _ = profiler.Begin(&inner);
    profiler.End();
    profiler.End();
    profiler.EndLoop();

    const player = try world.CreatePlayer(engine_context, Player.DefaultConfig);
    try std.testing.expect(!stats.IsShown());

    //shown: an overlay of the player's, the window open, with a row per profiler node and the memory tree from the engine
    try stats.Toggle(engine_context, player);
    try std.testing.expect(stats.IsShown());
    try std.testing.expect(try IsOverlayOf(player, stats.mScene.?));
    try std.testing.expect(stats.mPanel.IsOpen());
    engine_context.mDT = ProfilerPanel.REFRESH_SECONDS;
    try stats.Update(engine_context, &profiler);
    try std.testing.expectEqual(@as(usize, 3), stats.mPanel.mRows.items.len);
    const loop_row = stats.mPanel.mRows.items[1].Title.GetComponent(TextComponent).?.mText.items;
    try std.testing.expect(std.mem.startsWith(u8, loop_row, "Loop   "));
    try std.testing.expect(stats.mPanel.mMemoryRows.items.len > 1);
    //its rows are the Game world's
    try std.testing.expectEqual(world, stats.mPanel.mWindow.mManager);

    //an overlay the game adds goes on top, until the next pass puts the stats back over it
    const game_overlay = try world.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    const top = world.mSManager.mNumofLayers - 1;
    try std.testing.expectEqual(top, game_overlay.GetComponent(SceneStackPos).?.mPosition);
    try stats.Update(engine_context, &profiler);
    try std.testing.expectEqual(top, stats.mScene.?.GetComponent(SceneStackPos).?.mPosition);

    //hidden by the key: the player no longer shows it, the window is closed, and the scene is kept for the next time
    try stats.Toggle(engine_context, player);
    try std.testing.expect(!stats.IsShown());
    try std.testing.expect(!try IsOverlayOf(player, stats.mScene.?));
    try std.testing.expect(!stats.mPanel.IsOpen());
    try std.testing.expect(stats.mScene.?.IsActive());

    //shown again, then closed with the window's close button: the next pass hides it
    try stats.Toggle(engine_context, player);
    try std.testing.expect(stats.IsShown());
    try WidgetActions.CloseWindow(engine_context, stats.mPanel.mWindow);
    try stats.Update(engine_context, &profiler);
    try std.testing.expect(stats.mShowing == null);
    try std.testing.expect(!try IsOverlayOf(player, stats.mScene.?));
}
