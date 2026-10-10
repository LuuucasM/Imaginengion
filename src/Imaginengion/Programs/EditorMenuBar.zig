//! The editor's menu bar, built out of the editor UI's menu widgets (Widgets.MenuBar, Menu, MenuItem, Submenu): File,
//! Project (the scene, player and game mode the game starts from), Window and Editor (theme, play options, vsync). Opening, closing and switching menus is the stock menu scripts'.
//! What an item does is the editor's: this keeps which item is which action (ActionOf), and the editor runs the action when the item is clicked. Every frame
//! Update puts the editor's state on the items: which panels are shown (check marks), what can't be done right now
//! (greyed out, DisabledTag), and the players the play preview can follow, a list rebuilt when they change.
const std = @import("std");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const Player = @import("../ECSObjects/Player.zig");
const Project = @import("../Core/Project.zig");
const Widgets = @import("../UI/Widgets.zig");
const WidgetActions = @import("../UI/WidgetActions.zig");

const EditorMenuBar = @This();

/// The panels the Window menu shows and hides
pub const Panel = enum {
    AssetHandles,
    AudioBuses,
    Components,
    ContentBrowser,
    Scripts,
    Stats,
    PickingDebug,
    UIElement,
    Viewport,

    fn Title(self: Panel) []const u8 {
        return switch (self) {
            .AssetHandles => "Asset Handles",
            .AudioBuses => "Audio Buses",
            .Components => "Components",
            .ContentBrowser => "Content Browser",
            .Scripts => "Scripts",
            .Stats => "Stats",
            .PickingDebug => "Picking Debug",
            .UIElement => "UI Element",
            .Viewport => "Viewport",
        };
    }
};

/// What clicking an item does
pub const Action = union(enum) {
    NewGameScene,
    NewOverlayScene,
    OpenScene,
    SaveScene,
    SaveSceneAs,
    SaveEntity,
    SaveEntityAs,
    NewProject,
    OpenProject,
    SaveProject,
    /// pick the file the game starts from for this entry
    SetProjectEntry: Project.Entry,
    Exit,
    /// show the panel if it is hidden, hide it if it is shown
    TogglePanel: Panel,
    PickTheme,
    PlayStop,
    TogglePlayPreview,
    /// make the player the one the play preview follows, or stop following it if it already is
    FollowPlayer: Player,
    /// turn vsync off if it is on, on if it is off
    ToggleVSync,
};

/// The editor's state the items show, for Update
pub const State = struct {
    /// whether each panel is shown
    Shown: std.EnumArray(Panel, bool),
    ProjectOpen: bool,
    /// whether Play/Stop can be used: stopping always, starting with a run player that can be drawn
    CanPlayStop: bool,
    PlayPreview: bool,
    /// whether frames wait for the screen's refresh (Renderer.mPresentMode)
    VSync: bool,
    /// the players the play preview can follow, and the one it does
    Players: []const Player,
    Following: ?Player,
};

const ItemAction = struct {
    Item: Entity,
    Action: Action,
};

mActions: std.ArrayList(ItemAction) = .empty,
mPanelItems: std.EnumArray(Panel, Entity) = .initFill(.uninit),
mSaveProject: Entity = .uninit,
mEntryItems: std.EnumArray(Project.Entry, Entity) = .initFill(.uninit),
mPlayStop: Entity = .uninit,
mPlayPreview: Entity = .uninit,
mVSync: Entity = .uninit,
/// The Player Camera submenu, and its items, one per player, in the order of the players
mPlayersMenu: Entity = .uninit,
mPlayerItems: std.ArrayList(ItemAction) = .empty,
/// Whether its items get the stock menu scripts, for the ones Update makes
mStockScripts: bool = true,

/// Builds the menus into `bar` (a Widgets.MenuBar)
pub fn Build(engine_context: *EngineContext, bar: Entity, options: Widgets.Options) !EditorMenuBar {
    const zone = Tracy.ZoneInit("EditorMenuBar::Build", @src());
    defer zone.Deinit();
    var self: EditorMenuBar = .{ .mStockScripts = options.StockScripts };
    errdefer self.Deinit(engine_context.EngineAllocator());
    const item_options = Widgets.MenuItemOptions{ .StockScripts = options.StockScripts };
    const check_options = Widgets.MenuItemOptions{ .Checkable = true, .StockScripts = options.StockScripts };

    const file = try Widgets.Menu(engine_context, bar, "File", options);
    const new_scene = try Widgets.Submenu(engine_context, file, "New Scene", options);
    _ = try self.Add(engine_context, new_scene, "New Game Scene", item_options, .NewGameScene);
    _ = try self.Add(engine_context, new_scene, "New Overlay Scene", item_options, .NewOverlayScene);
    _ = try self.Add(engine_context, file, "Open Scene", item_options, .OpenScene);
    _ = try self.Add(engine_context, file, "Save Scene", item_options, .SaveScene);
    _ = try self.Add(engine_context, file, "Save Scene As...", item_options, .SaveSceneAs);
    _ = try Widgets.Separator(engine_context, .{ .Entity = file });
    _ = try self.Add(engine_context, file, "Save Entity", item_options, .SaveEntity);
    _ = try self.Add(engine_context, file, "Save Entity As...", item_options, .SaveEntityAs);
    _ = try Widgets.Separator(engine_context, .{ .Entity = file });
    _ = try self.Add(engine_context, file, "New Project", item_options, .NewProject);
    _ = try self.Add(engine_context, file, "Open Project", item_options, .OpenProject);
    self.mSaveProject = try self.Add(engine_context, file, "Save Project", item_options, .SaveProject);
    _ = try Widgets.Separator(engine_context, .{ .Entity = file });
    _ = try self.Add(engine_context, file, "Exit", item_options, .Exit);

    const project = try Widgets.Menu(engine_context, bar, "Project", options);
    const entry = try Widgets.Submenu(engine_context, project, "Set Project Entry", options);
    self.mEntryItems.set(.Scene, try self.Add(engine_context, entry, "Scene...", item_options, .{ .SetProjectEntry = .Scene }));
    self.mEntryItems.set(.Player, try self.Add(engine_context, entry, "Player...", item_options, .{ .SetProjectEntry = .Player }));
    self.mEntryItems.set(.GameContext, try self.Add(engine_context, entry, "Game Mode...", item_options, .{ .SetProjectEntry = .GameContext }));

    const window = try Widgets.Menu(engine_context, bar, "Window", options);
    for (std.enums.values(Panel)) |panel| {
        self.mPanelItems.set(panel, try self.Add(engine_context, window, panel.Title(), check_options, .{ .TogglePanel = panel }));
    }

    const editor = try Widgets.Menu(engine_context, bar, "Editor", options);
    _ = try self.Add(engine_context, editor, "UI Theme...", item_options, .PickTheme);
    const play_menu = try Widgets.Submenu(engine_context, editor, "Play Menu", options);
    self.mPlayStop = try self.Add(engine_context, play_menu, "Play/Stop", .{ .Shortcut = "F5", .StockScripts = options.StockScripts }, .PlayStop);
    self.mPlayPreview = try self.Add(engine_context, editor, "Use Preview Panel", check_options, .TogglePlayPreview);
    self.mPlayersMenu = try Widgets.Submenu(engine_context, editor, "Player Camera", options);
    _ = try Widgets.Separator(engine_context, .{ .Entity = editor });
    self.mVSync = try self.Add(engine_context, editor, "VSync", check_options, .ToggleVSync);
    return self;
}

pub fn Deinit(self: *EditorMenuBar, engine_allocator: std.mem.Allocator) void {
    self.mActions.deinit(engine_allocator);
    self.mPlayerItems.deinit(engine_allocator);
}

/// What clicking `item` does, null if it isn't one of the menu bar's items
pub fn ActionOf(self: *const EditorMenuBar, item: Entity) ?Action {
    for ([_][]const ItemAction{ self.mActions.items, self.mPlayerItems.items }) |actions| {
        for (actions) |entry| {
            if (entry.Item.mID == item.mID and entry.Item.mManager == item.mManager) return entry.Action;
        }
    }
    return null;
}

/// Puts the editor's state on the items: check marks, greyed out items, and the players to follow
pub fn Update(self: *EditorMenuBar, engine_context: *EngineContext, state: State) !void {
    const zone = Tracy.ZoneInit("EditorMenuBar::Update", @src());
    defer zone.Deinit();
    for (std.enums.values(Panel)) |panel| {
        try WidgetActions.SetChecked(engine_context, self.mPanelItems.get(panel), state.Shown.get(panel));
    }
    try WidgetActions.SetChecked(engine_context, self.mPlayPreview, state.PlayPreview);
    try WidgetActions.SetChecked(engine_context, self.mVSync, state.VSync);
    try WidgetActions.SetDisabled(engine_context, self.mSaveProject, !state.ProjectOpen);
    for (self.mEntryItems.values) |item| try WidgetActions.SetDisabled(engine_context, item, !state.ProjectOpen);
    try WidgetActions.SetDisabled(engine_context, self.mPlayStop, !state.CanPlayStop);

    try self.UpdatePlayers(engine_context, state.Players);
    for (self.mPlayerItems.items) |entry| {
        const following = if (state.Following) |player| player.mID == entry.Action.FollowPlayer.mID else false;
        try WidgetActions.SetChecked(engine_context, entry.Item, following);
    }
}

/// The Player Camera items, made again whenever the players change
fn UpdatePlayers(self: *EditorMenuBar, engine_context: *EngineContext, players: []const Player) !void {
    if (self.SamePlayers(players)) return;
    for (self.mPlayerItems.items) |entry| try entry.Item.Delete(engine_context);
    self.mPlayerItems.clearRetainingCapacity();
    for (players) |player| {
        const item = try Widgets.MenuItem(engine_context, self.mPlayersMenu, player.GetName(), .{ .Checkable = true, .StockScripts = self.mStockScripts });
        try self.mPlayerItems.append(engine_context.EngineAllocator(), .{ .Item = item, .Action = .{ .FollowPlayer = player } });
    }
}

fn SamePlayers(self: *const EditorMenuBar, players: []const Player) bool {
    if (players.len != self.mPlayerItems.items.len) return false;
    for (players, self.mPlayerItems.items) |player, entry| {
        if (player.mID != entry.Action.FollowPlayer.mID or player.mManager != entry.Action.FollowPlayer.mManager) return false;
    }
    return true;
}

/// A menu item that does `action`
fn Add(self: *EditorMenuBar, engine_context: *EngineContext, menu: Entity, text: []const u8, options: Widgets.MenuItemOptions, action: Action) !Entity {
    const item = try Widgets.MenuItem(engine_context, menu, text, options);
    try self.mActions.append(engine_context.EngineAllocator(), .{ .Item = item, .Action = action });
    return item;
}
