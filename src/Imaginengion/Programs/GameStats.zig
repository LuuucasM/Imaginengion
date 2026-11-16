//! The stats window of a game built with `zig build game -Dstats`: Ctrl+Shift+TOGGLE_KEY shows the editor's Profiler
//! window (EditorPanels/ProfilerPanel.zig) over the game, and hides it again. The same trees as in the editor: time by
//! zone, and memory from Application down to each component array, opened and folded by clicking their arrows. The
//! window's close button hides it too.
//! It is an overlay scene in the Game world, kept at the top of the scene stack so it draws over everything, and shown
//! through the shown player (Player.AddOverlay). So its rows count in the Game world's own numbers. Built without
//! -Dstats none of this is compiled in, and the profiler is never started.
const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const Profiler = @import("../Core/Profiler.zig");
const Tracy = @import("../Core/Tracy.zig");
const ScanCodes = @import("../Inputs/InputEnums.zig").ScanCodes;
const Scene = @import("../ECSObjects/Scene.zig");
const Player = @import("../ECSObjects/Player.zig");
const Widgets = @import("../UI/Widgets.zig");
const WidgetActions = @import("../UI/WidgetActions.zig");
const ProfilerPanel = @import("../EditorPanels/ProfilerPanel.zig");
const SceneStackPos = @import("../ECSComponents/SComponents.zig").StackPosComponent;

const GameStats = @This();

/// Whether the game was built with -Dstats
pub const enabled = @import("game_build_options").stats;
/// Shown and hidden with Ctrl+Shift+TOGGLE_KEY, out of the way of any game's own keys
pub const TOGGLE_KEY: ScanCodes = .F12;

/// Made the first time it is shown
mScene: ?Scene = null,
mPanel: ProfilerPanel = .{},
/// The child player showing it (Player.AddOverlay), null while hidden. Deleting it hides it again
mShowing: ?Player = null,
/// Off to build it without compiling the stock scripts, in a test
mOptions: Widgets.Options = .{},

/// Starts the profiler, whose numbers it shows. Its memory is the engine's, not the game's
pub fn Start(engine_context: *EngineContext) !void {
    try Profiler.gMain.Start(engine_context.Keep(), engine_context.Io());
}

pub fn Deinit(self: *GameStats, engine_context: *EngineContext) void {
    self.mPanel.Deinit(engine_context.mGameWorld.Keep());
    Profiler.gMain.Stop();
}

/// Whether a key press is Ctrl+Shift+TOGGLE_KEY: once a press, not again while it is held
pub fn IsToggle(engine_context: *EngineContext, key: ScanCodes, repeat: u8) bool {
    if (key != TOGGLE_KEY or repeat != 0) return false;
    const input = &engine_context.mInputManager;
    const ctrl = input.IsKeyPressedUnfiltered(.LCTRL) or input.IsKeyPressedUnfiltered(.RCTRL);
    const shift = input.IsKeyPressedUnfiltered(.LSHIFT) or input.IsKeyPressedUnfiltered(.RSHIFT);
    return ctrl and shift;
}

/// Shows it through `player`, the player whose view is on screen, or hides it
pub fn Toggle(self: *GameStats, engine_context: *EngineContext, player: Player) !void {
    if (self.mShowing != null) return self.Hide(engine_context);
    if (self.mScene == null) {
        const scene = try engine_context.mGameWorld.NewScene(engine_context, .OverlayLayer, .{ .bAddSceneName = true, .bAddSceneUUID = false });
        try scene.SetName(engine_context, "Stats");
        self.mScene = scene;
        self.mPanel = try ProfilerPanel.Build(engine_context, scene, .Game, self.mOptions);
    }
    self.mShowing = try player.AddOverlay(engine_context, self.mScene.?);
    if (!self.mPanel.IsOpen()) try self.mPanel.Toggle(engine_context);
}

pub fn IsShown(self: GameStats) bool {
    const child = self.mShowing orelse return false;
    return child.IsActive() and self.mPanel.IsOpen();
}

/// Once a pass of the loop, before layout: keeps it on top, and refreshes the window's rows
pub fn Update(self: *GameStats, engine_context: *EngineContext, profiler: *const Profiler) !void {
    const zone = Tracy.ZoneInit("GameStats::Update", @src());
    defer zone.Deinit();
    if (self.mShowing == null) return;
    //closed with its close button, or the player showing it went (a new one was made the shown one): hidden, and
    //Ctrl+Shift+TOGGLE_KEY shows it again
    if (!self.IsShown()) return self.Hide(engine_context);
    try self.KeepOnTop(engine_context);
    try self.mPanel.Update(engine_context, profiler);
}

fn Hide(self: *GameStats, engine_context: *EngineContext) !void {
    const child = self.mShowing orelse return;
    self.mShowing = null;
    if (self.mPanel.IsOpen()) try WidgetActions.CloseWindow(engine_context, self.mPanel.mWindow);
    if (child.IsActive()) try child.Delete(engine_context);
}

// at the top of the scene stack, over any overlay the game has added since
fn KeepOnTop(self: *GameStats, engine_context: *EngineContext) !void {
    const scene = self.mScene orelse return;
    const world = &engine_context.mGameWorld;
    const top = world.mSManager.mNumofLayers - 1;
    const position = (scene.GetComponent(SceneStackPos) orelse return).mPosition;
    if (position != top) try world.MoveScene(world.Scratch(), scene, top);
}
