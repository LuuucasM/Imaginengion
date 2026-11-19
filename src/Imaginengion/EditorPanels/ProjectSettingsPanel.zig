//! The Project Settings panel, in the editor's own UI: a floating window, opened from the Project menu, with the
//! project's own settings:
//!   - the game's name, which its window's title shows, in a text field kept when Enter is pressed or the field is
//!     left (its TextSubmitted, OnUIEvent)
//!   - the game window's icon, a PNG, with a Clear button to go back to none
//!   - a row per project entry (Project.Entry: the scene, player and game context the game starts from)
//!   - the target platforms (TargetPlatforms), a row each: a button making it the target the editor checks the game's
//!     memory against, its name, its CPU and video memory budgets in MB, and a Remove button; and an Add Platform button
//! A file setting shows its file, or "Not set" while it has none, in a box a file from the Content Browser can be
//! dropped on (OnDrop), and has a Browse... button that picks the file with a file dialog (ActionOf, Run). The fields
//! are given the project's settings again whenever they change (Project.mVersion, TargetPlatforms.mVersion), however
//! they were set. A budget that isn't a whole number of MB is shown as it was again
const std = @import("std");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Project = @import("../Core/Project.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const Widgets = @import("../UI/Widgets.zig");
const WidgetActions = @import("../UI/WidgetActions.zig");
const UIManager = @import("../UI/UIManager.zig");
const PlatformUtils = @import("../PlatformUtils/PlatformUtils.zig");
const TargetPlatforms = @import("../Core/TargetPlatforms.zig");
const PointerDroppedEvent = @import("../Events/PointerEventData.zig").PointerDroppedEvent;
const EntityUIEvent = @import("../Events/UIEventData.zig").EntityEvent;
const EntityComponents = @import("../ECSComponents/EComponents.zig");
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const TextComponent = EntityComponents.TextComponent;
const FileRefComponent = EntityComponents.FileRefComponent;
const MathTypes = @import("../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;

const ProjectSettingsPanel = @This();

/// Where the window opens, from the middle of the editor UI, and how big it is
const AT = Vec2(f32){ .x = -250, .y = 100 };
const SIZE = Vec2(f32){ .x = 560, .y = 480 };
/// How wide a platform's budget fields are, and its target button
const BUDGET_WIDTH: f32 = 90;
const TARGET_WIDTH: f32 = 110;
/// How wide a row's setting name is
const NAME_WIDTH: f32 = 110;
/// What a box says while its file isn't set
const NOT_SET = "Not set";
/// The kind of file a window icon has to be
const ICON_EXTENSION = ".png";

/// What clicking a button does
pub const Action = union(enum) {
    /// pick the entry's file with a file dialog
    BrowseEntry: Project.Entry,
    /// pick the window icon with a file dialog
    BrowseIcon,
    /// take the window icon away
    ClearIcon,
    /// make a target platform, by its index, the one the editor checks against
    MakeTarget: usize,
    RemovePlatform: usize,
    AddPlatform,
};

/// A target platform's row and its parts' entities: the text fields' texts, which TextSubmitted is sent from
const PlatformRow = struct {
    Row: Entity = .uninit,
    Target: Entity = .uninit,
    Name: Entity = .uninit,
    CPU: Entity = .uninit,
    Video: Entity = .uninit,
    Remove: Entity = .uninit,
};

/// A file setting's row: the box showing its file, and its Browse... button
const FileRow = struct {
    Box: Entity = .uninit,
    Browse: Entity = .uninit,
};

mWindow: Entity = .uninit,
/// The name's text field's text, which TextSubmitted is sent from
mName: Entity = .uninit,
mIcon: FileRow = .{},
mClearIcon: Entity = .uninit,
mEntries: std.EnumArray(Project.Entry, FileRow) = .initFill(.{}),
/// The project's settings the fields were last given (Project.mVersion)
mShownVersion: ?u32 = null,
/// A row for each platform there can be, hidden while there is no platform for it
mPlatforms: [TargetPlatforms.MAX_PLATFORMS]PlatformRow = @splat(.{}),
mAddPlatform: Entity = .uninit,
/// The platforms the rows were last given (TargetPlatforms.mVersion)
mShownPlatforms: ?u32 = null,

/// Builds the window, closed, at the top of `scene`
pub fn Build(engine_context: *EngineContext, scene: Scene, options: Widgets.Options) !ProjectSettingsPanel {
    const zone = Tracy.ZoneInit("ProjectSettingsPanel::Build", @src());
    defer zone.Deinit();
    const window = try Widgets.FloatingWindow(engine_context, scene, "Project Settings", SIZE, AT, options);
    var self = ProjectSettingsPanel{ .mWindow = window.Window };
    const content = window.Content;

    const name_row = try NamedRow(engine_context, content, "Name");
    self.mName = UIManager.LabelOf(try Widgets.TextField(engine_context, .{ .Entity = name_row }, "")).?;
    const icon_row = try NamedRow(engine_context, content, "Window Icon");
    self.mIcon = try AddFile(engine_context, icon_row, ICON_EXTENSION);
    self.mClearIcon = try Widgets.Button(engine_context, .{ .Entity = icon_row }, "Clear");

    _ = try Widgets.Separator(engine_context, .{ .Entity = content });
    _ = try Widgets.Label(engine_context, .{ .Entity = content }, "What the game starts from");
    inline for (comptime std.enums.values(Project.Entry)) |entry| {
        self.mEntries.set(entry, try AddFile(engine_context, try NamedRow(engine_context, content, EntryName(entry)), comptime std.mem.span(entry.FileExtension())));
    }

    _ = try Widgets.Separator(engine_context, .{ .Entity = content });
    _ = try Widgets.Label(engine_context, .{ .Entity = content }, "Target platforms: memory budgets in MB, the game's memory checked against the target's");
    for (&self.mPlatforms) |*platform| platform.* = try PlatformRowOf(engine_context, content);
    self.mAddPlatform = try Widgets.Button(engine_context, .{ .Entity = content }, "Add Platform");

    try WidgetActions.CloseWindow(engine_context, self.mWindow);
    return self;
}

/// A row as wide as `parent` starting with a setting's name
fn NamedRow(engine_context: *EngineContext, parent: Entity, name: []const u8) !Entity {
    const row = try Widgets.Row(engine_context, .{ .Entity = parent });
    row.GetComponentMut(LayoutItemComponent).?.mWidth = .{ .Fill = 1 };
    const label = try Widgets.Label(engine_context, .{ .Entity = row }, name);
    label.GetComponentMut(LayoutItemComponent).?.mWidth = .{ .Fixed = NAME_WIDTH };
    return row;
}

/// A platform's row: its target button, its name, its budgets, its Remove
fn PlatformRowOf(engine_context: *EngineContext, parent: Entity) !PlatformRow {
    const row = try Widgets.Row(engine_context, .{ .Entity = parent });
    row.GetComponentMut(LayoutItemComponent).?.mWidth = .{ .Fill = 1 };
    const target = try Widgets.Button(engine_context, .{ .Entity = row }, "");
    target.GetComponentMut(LayoutItemComponent).?.mWidth = .{ .Fixed = TARGET_WIDTH };
    const name = try Widgets.TextField(engine_context, .{ .Entity = row }, "");
    const cpu = try Widgets.TextField(engine_context, .{ .Entity = row }, "");
    cpu.GetComponentMut(LayoutItemComponent).?.mWidth = .{ .Fixed = BUDGET_WIDTH };
    const video = try Widgets.TextField(engine_context, .{ .Entity = row }, "");
    video.GetComponentMut(LayoutItemComponent).?.mWidth = .{ .Fixed = BUDGET_WIDTH };
    return .{
        .Row = row,
        .Target = target,
        .Name = UIManager.LabelOf(name).?,
        .CPU = UIManager.LabelOf(cpu).?,
        .Video = UIManager.LabelOf(video).?,
        .Remove = try Widgets.Button(engine_context, .{ .Entity = row }, "Remove"),
    };
}

/// A file setting's box a file with `extension` can be dropped on and its Browse..., at the end of `row`
fn AddFile(engine_context: *EngineContext, row: Entity, comptime extension: []const u8) !FileRow {
    return .{
        .Box = try Widgets.DropBox(engine_context, .{ .Entity = row }, NOT_SET, EntityComponents.DropTargetComponent.Files(&.{extension})),
        .Browse = try Widgets.Button(engine_context, .{ .Entity = row }, "Browse..."),
    };
}

/// What the editor calls an entry
fn EntryName(entry: Project.Entry) []const u8 {
    return switch (entry) {
        .Scene => "Scene",
        .Player => "Player",
        .GameContext => "Game Context",
    };
}

pub fn IsOpen(self: ProjectSettingsPanel) bool {
    return WidgetActions.IsWindowOpen(self.mWindow);
}

/// Opens the window in front of the others, or closes it
pub fn Toggle(self: ProjectSettingsPanel, engine_context: *EngineContext) !void {
    if (self.IsOpen()) {
        try WidgetActions.CloseWindow(engine_context, self.mWindow);
    } else {
        try WidgetActions.OpenWindow(engine_context, self.mWindow);
    }
}

/// Once a frame, before layout, while it is open: the fields given the project's settings again if they have changed
pub fn Update(self: *ProjectSettingsPanel, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("ProjectSettingsPanel::Update", @src());
    defer zone.Deinit();
    if (!self.IsOpen()) return;
    try self.ShowPlatforms(engine_context);
    const project = &engine_context.mProject;
    if (self.mShownVersion == project.mVersion) return;
    try WidgetActions.SetText(engine_context, self.mName, project.GetName());
    try ShowFile(engine_context, self.mIcon.Box, project.GetWindowIcon());
    for (std.enums.values(Project.Entry)) |entry| try ShowFile(engine_context, self.mEntries.get(entry).Box, project.GetEntry(entry));
    self.mShownVersion = project.mVersion;
}

/// The platforms' rows given the platforms again if they have changed: a row shown for each platform, the rest hidden
fn ShowPlatforms(self: *ProjectSettingsPanel, engine_context: *EngineContext) !void {
    const platforms = &engine_context.mTargetPlatforms;
    if (self.mShownPlatforms == platforms.mVersion) return;
    var number: [16]u8 = undefined;
    for (self.mPlatforms, 0..) |row, index| {
        const shown = index < platforms.Count();
        try SetShown(engine_context, row.Row, shown);
        if (!shown) continue;
        const platform = platforms.Get(index);
        try WidgetActions.SetText(engine_context, UIManager.LabelOf(row.Target).?, if (index == platforms.mTarget) "Target" else "Make Target");
        try WidgetActions.SetText(engine_context, row.Name, platforms.GetName(index));
        try WidgetActions.SetText(engine_context, row.CPU, try std.fmt.bufPrint(&number, "{d}", .{platform.mCPUMemoryMB}));
        try WidgetActions.SetText(engine_context, row.Video, try std.fmt.bufPrint(&number, "{d}", .{platform.mVideoMemoryMB}));
    }
    self.mShownPlatforms = platforms.mVersion;
}

/// Shows or hides a row, through its layout item
fn SetShown(engine_context: *EngineContext, entity: Entity, shown: bool) !void {
    const item = entity.GetComponentMut(LayoutItemComponent) orelse return;
    if (item.mCollapsed == !shown) return;
    item.mCollapsed = !shown;
    try entity.MarkLayoutDirty(engine_context);
}

fn ShowFile(engine_context: *EngineContext, box: Entity, path: []const u8) !void {
    try WidgetActions.SetText(engine_context, box, if (path.len > 0) path else NOT_SET);
}

/// What clicking `button` does, null if it isn't one of the panel's buttons
pub fn ActionOf(self: *const ProjectSettingsPanel, button: Entity) ?Action {
    if (Same(self.mIcon.Browse, button)) return .BrowseIcon;
    if (Same(self.mClearIcon, button)) return .ClearIcon;
    for (std.enums.values(Project.Entry)) |entry| {
        if (Same(self.mEntries.get(entry).Browse, button)) return .{ .BrowseEntry = entry };
    }
    if (Same(self.mAddPlatform, button)) return .AddPlatform;
    for (self.mPlatforms, 0..) |row, index| {
        if (Same(row.Target, button)) return .{ .MakeTarget = index };
        if (Same(row.Remove, button)) return .{ .RemovePlatform = index };
    }
    return null;
}

/// Does what a button asked for: a Browse... sets its file to the one picked in a file dialog, if one is
pub fn Run(engine_context: *EngineContext, action: Action) !void {
    switch (action) {
        .BrowseEntry => |entry| {
            const abs_path = try PlatformUtils.OpenFile(engine_context.ProgramScratch(), entry.FileExtension());
            if (abs_path.len > 0) try SetEntry(engine_context, entry, abs_path);
        },
        .BrowseIcon => {
            const abs_path = try PlatformUtils.OpenFile(engine_context.ProgramScratch(), ICON_EXTENSION);
            if (abs_path.len > 0) try SetWindowIcon(engine_context, abs_path);
        },
        .ClearIcon => try SetWindowIcon(engine_context, ""),
        .MakeTarget => |index| engine_context.mTargetPlatforms.SetTarget(index),
        .RemovePlatform => |index| engine_context.mTargetPlatforms.Remove(index) catch |err| switch (err) {
            error.LastPlatform => std.log.warn("A project always has a target platform: the last one can't be removed", .{}),
        },
        .AddPlatform => engine_context.mTargetPlatforms.Add() catch |err| switch (err) {
            error.TooManyPlatforms => std.log.warn("A project has at most {d} target platforms", .{TargetPlatforms.MAX_PLATFORMS}),
            else => return err,
        },
    }
}

/// A drop on the panel: a file from the Content Browser on a file setting's box becomes that setting
pub fn OnDrop(self: *const ProjectSettingsPanel, engine_context: *EngineContext, on: Entity, dropped: PointerDroppedEvent) !void {
    const file_ref = dropped.mSource.GetComponent(FileRefComponent) orelse return;
    const rel_path = file_ref.mRelPath.items;
    if (Same(self.mIcon.Box, on)) {
        if (file_ref.mPathType != .Prj) return std.log.warn("The window icon has to be a file inside the project folder, not {s}", .{rel_path});
        return try SetWindowIcon(engine_context, try engine_context.mProject.GetAbsPath(engine_context.ProgramScratch(), rel_path));
    }
    for (std.enums.values(Project.Entry)) |entry| {
        if (!Same(self.mEntries.get(entry).Box, on)) continue;
        if (file_ref.mPathType != .Prj) return std.log.warn("The project's entry {s} has to be a file inside the project folder, not {s}", .{ EntryName(entry), rel_path });
        return try SetEntry(engine_context, entry, try engine_context.mProject.GetAbsPath(engine_context.ProgramScratch(), rel_path));
    }
}

/// One of the frame's UI events: the name field's text kept renames the game
pub fn OnUIEvent(self: *ProjectSettingsPanel, engine_context: *EngineContext, event: EntityUIEvent) !void {
    const submitted = switch (event.mEvent) {
        .TextSubmitted => |e| e.mTarget,
        else => return,
    };
    //one event per entity in the chain: the field's own
    if (!Same(event.mEntity, submitted)) return;
    if (try self.SubmitPlatform(engine_context, submitted)) return;
    if (!Same(submitted, self.mName)) return;
    const text = self.mName.GetComponent(TextComponent) orelse return;
    engine_context.mProject.SetName(engine_context, text.mText.items) catch |err| switch (err) {
        error.NoProjectOpen => std.log.warn("Open a project before naming it", .{}),
        else => return err,
    };
    //shown the project's name again: with no project open, nothing was kept
    self.mShownVersion = null;
}

/// A platform field's text kept: a name renames the platform, a budget is set if it's a whole number of MB. True if
/// `field` was one of them. What was typed may not be what was kept, so the rows are shown the platforms again
fn SubmitPlatform(self: *ProjectSettingsPanel, engine_context: *EngineContext, field: Entity) !bool {
    const platforms = &engine_context.mTargetPlatforms;
    for (self.mPlatforms[0..platforms.Count()], 0..) |row, index| {
        const text = (field.GetComponent(TextComponent) orelse return false).mText.items;
        if (Same(field, row.Name)) {
            platforms.SetName(index, text);
        } else if (Same(field, row.CPU) or Same(field, row.Video)) {
            const mb = std.fmt.parseUnsigned(u32, std.mem.trim(u8, text, " \t"), 10) catch {
                std.log.warn("A budget is a whole number of MB, not {s}", .{text});
                self.mShownPlatforms = null;
                return true;
            };
            if (Same(field, row.CPU)) platforms.SetCPUMemoryMB(index, mb) else platforms.SetVideoMemoryMB(index, mb);
        } else continue;
        self.mShownPlatforms = null;
        return true;
    }
    return false;
}

/// Makes the file at abs_path the project's `entry`, or says why it can't be
fn SetEntry(engine_context: *EngineContext, entry: Project.Entry, abs_path: []const u8) !void {
    engine_context.mProject.SetEntry(engine_context, entry, abs_path) catch |err| switch (err) {
        error.NoProjectOpen => return std.log.warn("Open a project before setting its entries", .{}),
        error.NotInProject, error.WrongFileKind => return std.log.warn("The project's entry {s} has to be a {s} file inside the project folder, not {s}", .{ EntryName(entry), std.mem.span(entry.FileExtension()), abs_path }),
        else => return err,
    };
}

/// Makes the image at abs_path the game window's icon, or none for an empty abs_path, or says why it can't be
fn SetWindowIcon(engine_context: *EngineContext, abs_path: []const u8) !void {
    engine_context.mProject.SetWindowIcon(engine_context, abs_path) catch |err| switch (err) {
        error.NoProjectOpen => return std.log.warn("Open a project before setting its window icon", .{}),
        error.NotInProject, error.WrongFileKind => return std.log.warn("The window icon has to be a {s} file inside the project folder, not {s}", .{ ICON_EXTENSION, abs_path }),
        else => return err,
    };
}

fn Same(a: Entity, b: Entity) bool {
    return a.mID == b.mID and a.mManager == b.mManager;
}
