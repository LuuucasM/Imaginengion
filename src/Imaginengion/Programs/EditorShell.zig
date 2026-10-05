//! The editor's shell: how the window is split up, built out of the editor UI's own widgets under its root. The menu bar
//! along the top; the viewport in the middle with the play preview under it; down the right the hierarchy panels in
//! tabs, the components and scripts panels in tabs, and the content browser. Every pane has a tab bar naming what is in
//! it, a single tab for the panes that hold one thing. Dividers move the splits and tabs switch pages, through the stock
//! widget scripts.
//! While a panel is still drawn by ImGui, its pane hosts it: every frame its ImGui window is put where the pane is laid
//! out (Host), and isn't drawn at all while the pane is hidden. Porting a panel puts real widgets in the same pane.
const std = @import("std");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const Widgets = @import("../UI/Widgets.zig");
const ImGui = @import("../Imgui/Imgui.zig");
const MathTypes = @import("../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const LayoutComponent = EntityComponents.LayoutComponent;
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const TransformComponent = EntityComponents.TransformComponent;
const EntityChildComponent = @import("../ECS/Components.zig").ChildComponent(Entity.Type);

const EditorShell = @This();

/// How wide the right column starts, how tall the hierarchy tabs, the content browser and the play preview start, in
/// canvas units (the editor UI's are window points at the display's scale)
const RIGHT_COLUMN_WIDTH: f32 = 320;
const HIERARCHY_HEIGHT: f32 = 300;
const CONTENT_BROWSER_HEIGHT: f32 = 280;
const PLAY_PREVIEW_HEIGHT: f32 = 300;

/// The menu bar along the top, for the menus to go in (EditorMenuBar.zig)
mMenuBar: Entity = .uninit,
/// The viewport's views go in here (EditorProgram.UpdateViewportArea)
mViewportArea: Entity = .uninit,
/// The middle column's split: the viewport above the play preview
mCenter: Widgets.SplitParts = undefined,
/// The panes and pages the ImGui panels are hosted in
mPlayPane: Entity = .uninit,
mScenesPage: Entity = .uninit,
mEntitiesPage: Entity = .uninit,
mPlayersPage: Entity = .uninit,
mGameModesPage: Entity = .uninit,
mComponentsPage: Entity = .uninit,
mScriptsPage: Entity = .uninit,
mContentBrowserPane: Entity = .uninit,

/// Builds the shell under `root`, a column filling the window
pub fn Build(engine_context: *EngineContext, root: Entity, options: Widgets.Options) !EditorShell {
    const zone = Tracy.ZoneInit("EditorShell::Build", @src());
    defer zone.Deinit();
    var self: EditorShell = .{};

    self.mMenuBar = try Widgets.MenuBar(engine_context, .{ .Entity = root });
    try self.mMenuBar.SetName(engine_context, "Menu Bar");

    const main = try Widgets.Split(engine_context, .{ .Entity = root }, .Row, .Second, RIGHT_COLUMN_WIDTH, options);
    try main.Root.SetName(engine_context, "Shell");

    //the middle: the viewport, and the play preview under it
    self.mCenter = try Widgets.Split(engine_context, .{ .Entity = main.First }, .Column, .Second, PLAY_PREVIEW_HEIGHT, options);
    const viewport_page = try SingleTab(engine_context, self.mCenter.First, "Viewport", options);
    self.mViewportArea = try viewport_page.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    try self.mViewportArea.SetName(engine_context, "Viewport Area");
    //in front of the pane it is in, like everything a widget builder makes
    try self.mViewportArea.SetTranslation(engine_context, Vec3(f32){ .x = 0, .y = 0, .z = Widgets.DEPTH_STEP });
    _ = try self.mViewportArea.AddComponent(engine_context, LayoutComponent{});
    _ = try self.mViewportArea.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fill = 1 }, .mHeight = .{ .Fill = 1 } });
    self.mPlayPane = try SingleTab(engine_context, self.mCenter.Second, "Play", options);

    //down the right: the hierarchies, the components and scripts, the content browser
    const right = try Widgets.Split(engine_context, .{ .Entity = main.Second }, .Column, .First, HIERARCHY_HEIGHT, options);
    const hierarchy = try Widgets.Tabs(engine_context, .{ .Entity = right.First });
    self.mScenesPage = try Widgets.AddTab(engine_context, hierarchy, "Scenes", options);
    self.mEntitiesPage = try Widgets.AddTab(engine_context, hierarchy, "Entities", options);
    self.mPlayersPage = try Widgets.AddTab(engine_context, hierarchy, "Players", options);
    self.mGameModesPage = try Widgets.AddTab(engine_context, hierarchy, "Game Modes", options);

    const lower = try Widgets.Split(engine_context, .{ .Entity = right.Second }, .Column, .Second, CONTENT_BROWSER_HEIGHT, options);
    const inspector = try Widgets.Tabs(engine_context, .{ .Entity = lower.First });
    self.mComponentsPage = try Widgets.AddTab(engine_context, inspector, "Components", options);
    self.mScriptsPage = try Widgets.AddTab(engine_context, inspector, "Scripts", options);
    self.mContentBrowserPane = try SingleTab(engine_context, lower.Second, "Content Browser", options);
    return self;
}

/// A tab bar with one tab naming what is in `pane`, and the page under it that holds it
fn SingleTab(engine_context: *EngineContext, pane: Entity, title: []const u8, options: Widgets.Options) !Entity {
    const tabs = try Widgets.Tabs(engine_context, .{ .Entity = pane });
    return try Widgets.AddTab(engine_context, tabs, title, options);
}

/// Shows or hides the play preview under the viewport, and the divider above it
pub fn ShowPlayPreview(self: EditorShell, engine_context: *EngineContext, shown: bool) !void {
    for ([_]Entity{ self.mCenter.Divider, self.mCenter.Second }) |entity| {
        const item = entity.GetComponent(LayoutItemComponent).?;
        if (item.mCollapsed == !shown) continue;
        item.mCollapsed = !shown;
        try entity.MarkLayoutDirty(engine_context);
    }
}

/// Puts the next ImGui panel window where `pane` is laid out, if the pane is shown and the panel is `open`. Returns
/// whether to draw the panel: a hidden pane (a tab not selected) draws nothing. The panel's own igBegin takes its
/// flags from ImGui.PanelFlags, which keeps it where it is put
pub fn Host(pane: Entity, open: bool, engine_context: *EngineContext) bool {
    const zone = Tracy.ZoneInit("EditorShell::Host", @src());
    defer zone.Deinit();
    if (!open or !IsShown(pane)) return false;
    const window_size = Vec2(f32){ .x = @floatFromInt(engine_context.mAppWindow.GetWidth()), .y = @floatFromInt(engine_context.mAppWindow.GetHeight()) };
    const rect = WindowRect(pane, window_size, engine_context.mAppWindow.GetDisplayScale()) orelse return false;
    ImGui.HostNextPanel(rect.Pos, rect.Size);
    return true;
}

/// A window rectangle: from its top left corner, in window points (the mouse's)
pub const Rect = struct {
    Pos: Vec2(f32),
    Size: Vec2(f32),
};

/// Where a laid out editor UI entity is in the window: its laid out size around its position, which layout puts at its
/// center. The editor UI's canvas has its origin at the window's center with y up, and keeps a constant pixel size, so a
/// canvas unit is `display_scale` window points. Null for one that hasn't been laid out
pub fn WindowRect(entity: Entity, window_size: Vec2(f32), display_scale: f32) ?Rect {
    const item = entity.GetComponent(LayoutItemComponent) orelse return null;
    const transform = entity.GetComponent(TransformComponent) orelse return null;
    const center = transform.GetWorldPosition();
    const size = item.mComputedSize;
    return .{
        .Pos = .{
            .x = window_size.x / 2 + (center.x - size.x / 2) * display_scale,
            .y = window_size.y / 2 - (center.y + size.y / 2) * display_scale,
        },
        .Size = .{ .x = size.x * display_scale, .y = size.y * display_scale },
    };
}

/// Whether an entity and everything it is inside are shown: none of them collapsed
pub fn IsShown(entity: Entity) bool {
    var current = entity;
    while (true) {
        if (current.GetComponent(LayoutItemComponent)) |item| {
            if (item.mCollapsed) return false;
        }
        const child_component = current.GetComponent(EntityChildComponent) orelse return true;
        current = Entity{ .mID = child_component.mParent, .mManager = current.mManager };
    }
}
