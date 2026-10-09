//! The Content Browser, in the editor's own UI, in the shell's Content Browser pane: the open project's files, one
//! folder at a time, as a grid of tiles (an icon and the file's name). Folders come first, then files, each by name,
//! and only the kinds the editor uses are shown: folders, textures (.png), object files (.imen, .imsc...), scripts
//! (.zig), audio and fonts (.ttf, .otf). Double clicking a folder goes into it, Back goes up a folder, and an object file opens as a
//! template. Every file's tile can be dragged, carrying the file (FileRefComponent), e.g. a script onto the Scripts
//! panel. Right clicking the pane offers New Scene Layer. Every frame the folder is listed and checked against what
//! the tiles were built from, so files added or removed on disk show up
const std = @import("std");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const AssetHandle = @import("../ECSObjects/AssetHandle.zig");
const Serializer = @import("../Serializer/Serializer.zig");
const UIManager = @import("../UI/UIManager.zig");
const Widgets = @import("../UI/Widgets.zig");
const WidgetActions = @import("../UI/WidgetActions.zig");
const EntityComponents = @import("../ECSComponents/EComponents.zig");
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const SurfaceComponent = EntityComponents.SurfaceComponent;
const DragSourceComponent = EntityComponents.DragSourceComponent;
const FileRefComponent = EntityComponents.FileRefComponent;

const ContentBrowserPanel = @This();

/// How wide a tile is, and the gap between tiles
const TILE_WIDTH: f32 = 80;
const TILE_GAP: f32 = 4;
/// The most of a name a tile shows: a longer one is shortened to fit, ending in "..."
const MAX_NAME_LEN = 12;

/// What a tile is
pub const Kind = enum { Back, Folder, Texture, Object, Script, Audio, Font };

/// The icon each kind of tile shows
pub const Icons = struct {
    Back: AssetHandle = .uninit,
    Folder: AssetHandle = .uninit,
    Texture: AssetHandle = .uninit,
    Object: AssetHandle = .uninit,
    Script: AssetHandle = .uninit,
    Audio: AssetHandle = .uninit,
    Font: AssetHandle = .uninit,

    /// The engine's icon textures
    pub fn Load(engine_context: *EngineContext) !Icons {
        const Get = struct {
            fn Texture(ec: *EngineContext, rel_path: []const u8) !AssetHandle {
                return try ec.mAssetManager.GetAssetHandle(ec, .{ .File = .{ .rel_path = rel_path, .path_type = .Eng } });
            }
        };
        return .{
            .Back = try Get.Texture(engine_context, "src/Imaginengion/EngineAssets/textures/backarrowicon.png"),
            .Folder = try Get.Texture(engine_context, "src/Imaginengion/EngineAssets/textures/foldericon.png"),
            .Texture = try Get.Texture(engine_context, "src/Imaginengion/EngineAssets/textures/pngicon.png"),
            .Object = try Get.Texture(engine_context, "src/Imaginengion/EngineAssets/textures/sceneicon.png"),
            .Script = try Get.Texture(engine_context, "src/Imaginengion/EngineAssets/textures/scripticon.png"),
            .Audio = try Get.Texture(engine_context, "src/Imaginengion/EngineAssets/textures/mp3.png"),
            //no font icon yet: a document's, which the script one is
            .Font = try Get.Texture(engine_context, "src/Imaginengion/EngineAssets/textures/scripticon.png"),
        };
    }

    fn Release(self: *Icons) void {
        inline for (@typeInfo(Icons).@"struct".field_names) |name| @field(self, name).ReleaseAsset();
    }

    fn Of(self: Icons, kind: Kind) AssetHandle {
        return switch (kind) {
            inline else => |tag| @field(self, @tagName(tag)),
        };
    }
};

/// What clicking on the panel does
pub const Action = union(enum) {
    /// up a folder
    Up,
    /// into the folder of the tile at this place among the tiles
    Enter: usize,
    /// opens the object file of the tile at this place as a template
    Open: usize,
    /// a new game scene, from the pane's right-click menu
    NewScene,
};

/// A file or folder in the folder being shown
const Listed = struct {
    Kind: Kind,
    Name: []const u8,
};

const Tile = struct {
    Entity: Entity,
    Kind: Kind,
    /// where its name is in mNames
    NameStart: usize,
    NameLen: usize,
};

/// The panel's content, in its pane
mArea: Entity = .uninit,
/// Why there is nothing to show, folded away when there is
mMessage: Entity = .uninit,
/// The New Scene Layer item of the pane's right-click menu
mNewScene: Entity = .uninit,
/// The grid of tiles, null while none is built
mGrid: ?Entity = null,
mTiles: std.ArrayList(Tile) = .empty,
/// The tiles' names, one after the other
mNames: std.ArrayList(u8) = .empty,
/// The project's folder, which is as far up as it goes, and the folder being shown, empty with no project open
mRoot: std.ArrayList(u8) = .empty,
mPath: std.ArrayList(u8) = .empty,
/// The folder and its listing as they were when the tiles were built, to tell when they change
mBuiltFrom: std.ArrayList(u8) = .empty,
mIcons: Icons = .{},
mOptions: Widgets.Options = .{},

/// Builds the panel into `page`, the shell's Content Browser pane, with no project to show yet
pub fn Build(engine_context: *EngineContext, page: Entity, icons: Icons, options: Widgets.Options) !ContentBrowserPanel {
    const zone = Tracy.ZoneInit("ContentBrowserPanel::Build", @src());
    defer zone.Deinit();
    const area = try Widgets.ScrollArea(engine_context, .{ .Entity = page });
    //a background, so a right click on the empty part of the pane lands on the panel
    _ = try area.AddComponent(engine_context, SurfaceComponent{});
    try UIManager.Style(engine_context, area, "Window");
    const menu = try Widgets.ContextMenu(engine_context, area, options);
    return .{
        .mArea = area,
        .mMessage = try Widgets.Label(engine_context, .{ .Entity = area }, ""),
        .mNewScene = try Widgets.MenuItem(engine_context, menu, "New Scene Layer", .{ .StockScripts = options.StockScripts }),
        .mIcons = icons,
        .mOptions = options,
    };
}

pub fn Deinit(self: *ContentBrowserPanel, engine_allocator: std.mem.Allocator) void {
    self.mIcons.Release();
    self.mTiles.deinit(engine_allocator);
    self.mNames.deinit(engine_allocator);
    self.mRoot.deinit(engine_allocator);
    self.mPath.deinit(engine_allocator);
    self.mBuiltFrom.deinit(engine_allocator);
}

/// Whether it is shown in its pane (the Window menu's Content Browser)
pub fn IsOpen(self: ContentBrowserPanel) bool {
    return !self.mArea.GetComponent(LayoutItemComponent).?.mCollapsed;
}

pub fn Toggle(self: ContentBrowserPanel, engine_context: *EngineContext) !void {
    const item = self.mArea.GetComponent(LayoutItemComponent).?;
    item.mCollapsed = !item.mCollapsed;
    try self.mArea.MarkLayoutDirty(engine_context);
}

/// Shows `root`'s files, from its top: the project just opened or made
pub fn SetRoot(self: *ContentBrowserPanel, engine_context: *EngineContext, root: []const u8) !void {
    const engine_allocator = engine_context.EngineAllocator();
    self.mRoot.clearRetainingCapacity();
    try self.mRoot.appendSlice(engine_allocator, root);
    self.mPath.clearRetainingCapacity();
    try self.mPath.appendSlice(engine_allocator, root);
}

/// The folder being shown, as an absolute path. Empty with no project open
pub fn CurrentPath(self: ContentBrowserPanel) []const u8 {
    return self.mPath.items;
}

/// Once a frame, before layout, while it is shown: the folder listed, and the tiles built again if it changed
pub fn Update(self: *ContentBrowserPanel, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("ContentBrowserPanel::Update", @src());
    defer zone.Deinit();
    if (!self.IsOpen()) return;
    const frame_allocator = engine_context.FrameAllocator();

    if (self.mPath.items.len == 0) {
        if (self.mGrid != null) try self.Rebuild(engine_context, &.{}, "");
        return try ShowLine(engine_context, self.mMessage, "Open a project to see its files");
    }
    const listing = ListFolder(engine_context, self.mPath.items) catch |err| {
        //gone from disk, or can't be read: back to the top of the project
        std.log.warn("The content browser can't show {s} ({s})", .{ self.mPath.items, @errorName(err) });
        self.mPath.clearRetainingCapacity();
        try self.mPath.appendSlice(engine_context.EngineAllocator(), self.mRoot.items);
        return;
    };
    try ShowLine(engine_context, self.mMessage, "");

    //what the tiles show, as one string to compare: the folder, then each kind and name
    var built_from: std.ArrayList(u8) = .empty;
    try built_from.appendSlice(frame_allocator, self.mPath.items);
    for (listing) |listed| try built_from.print(frame_allocator, "\n{s}:{s}", .{ @tagName(listed.Kind), listed.Name });
    if (std.mem.eql(u8, built_from.items, self.mBuiltFrom.items) and self.mGrid != null) return;
    try self.Rebuild(engine_context, listing, built_from.items);
}

/// What a click on `entity` does: a double click on a folder, Back, or an object file, or New Scene Layer from the
/// pane's menu. Null for anything else
pub fn ActionOf(self: *const ContentBrowserPanel, entity: Entity, clicks: u8) ?Action {
    if (Same(entity, self.mNewScene)) return .NewScene;
    if (clicks != 2) return null;
    for (self.mTiles.items, 0..) |tile, i| {
        if (!Same(tile.Entity, entity)) continue;
        return switch (tile.Kind) {
            .Back => .Up,
            .Folder => .{ .Enter = i },
            .Object => .{ .Open = i },
            .Texture, .Script, .Audio, .Font => null,
        };
    }
    return null;
}

/// Does what a click asked for, other than NewScene, which is the editor's (its menu bar's New Game Scene). A new
/// folder's tiles are built the next frame
pub fn Run(self: *ContentBrowserPanel, engine_context: *EngineContext, action: Action) !void {
    switch (action) {
        .Up => {
            if (self.mPath.items.len <= self.mRoot.items.len) return;
            const last_slash = std.mem.lastIndexOfAny(u8, self.mPath.items, "/\\") orelse return;
            self.mPath.shrinkRetainingCapacity(@max(last_slash, self.mRoot.items.len));
        },
        .Enter => |index| {
            const name = self.NameOf(index);
            try self.mPath.print(engine_context.EngineAllocator(), "/{s}", .{name});
        },
        .Open => |index| {
            const rel_path = try self.RelPath(engine_context.FrameAllocator(), self.NameOf(index));
            const tmpl = try engine_context.mAssetManager.GetAssetHandle(engine_context, .{ .File = .{ .rel_path = rel_path, .path_type = .Prj } });
            try engine_context.mEditorEventManager.Insert(engine_context.EngineAllocator(), .EndOfFrame, .{ .OpenTmplEvent = .{ .mTmpl = tmpl } });
        },
        .NewScene => {},
    }
}

fn NameOf(self: ContentBrowserPanel, index: usize) []const u8 {
    const tile = self.mTiles.items[index];
    return self.mNames.items[tile.NameStart..][0..tile.NameLen];
}

/// A file in the folder being shown, as a path from the project's folder
fn RelPath(self: ContentBrowserPanel, frame_allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    const inside = std.mem.trimStart(u8, self.mPath.items[self.mRoot.items.len..], "/\\");
    if (inside.len == 0) return name;
    return try std.fmt.allocPrint(frame_allocator, "{s}/{s}", .{ inside, name });
}

/// The folder's folders and the files the editor uses, folders first and then files, each by name
fn ListFolder(engine_context: *EngineContext, path: []const u8) ![]Listed {
    const frame_allocator = engine_context.FrameAllocator();
    const io = engine_context.Io();
    var dir = try std.Io.Dir.openDirAbsolute(io, path, .{ .iterate = true });
    defer dir.close(io);

    var listing: std.ArrayList(Listed) = .empty;
    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        const kind: Kind = if (entry.kind == .directory) .Folder else KindOf(entry.name) orelse continue;
        try listing.append(frame_allocator, .{ .Kind = kind, .Name = try frame_allocator.dupe(u8, entry.name) });
    }
    std.mem.sort(Listed, listing.items, {}, struct {
        fn Before(_: void, a: Listed, b: Listed) bool {
            if ((a.Kind == .Folder) != (b.Kind == .Folder)) return a.Kind == .Folder;
            return std.mem.lessThan(u8, a.Name, b.Name);
        }
    }.Before);
    return listing.items;
}

/// What kind of file the editor shows a file as, null for one it doesn't show
fn KindOf(name: []const u8) ?Kind {
    const extension = std.fs.path.extension(name);
    if (std.mem.eql(u8, extension, ".png")) return .Texture;
    if (std.mem.eql(u8, extension, ".zig")) return .Script;
    if (std.mem.eql(u8, extension, ".mp3") or std.mem.eql(u8, extension, ".wav") or std.mem.eql(u8, extension, ".flac")) return .Audio;
    if (std.mem.eql(u8, extension, ".ttf") or std.mem.eql(u8, extension, ".otf")) return .Font;
    if (Serializer.ObjectKindOf(extension) != null) return .Object;
    return null;
}

/// The old tiles hidden and deleted, and new ones built for `listing`
fn Rebuild(self: *ContentBrowserPanel, engine_context: *EngineContext, listing: []const Listed, built_from: []const u8) !void {
    const zone = Tracy.ZoneInit("ContentBrowserPanel::Rebuild", @src());
    defer zone.Deinit();
    const engine_allocator = engine_context.EngineAllocator();
    if (self.mGrid) |grid| try Widgets.Remove(engine_context, grid, &.{});
    self.mGrid = null;
    self.mTiles.clearRetainingCapacity();
    self.mNames.clearRetainingCapacity();
    self.mBuiltFrom.clearRetainingCapacity();
    try self.mBuiltFrom.appendSlice(engine_allocator, built_from);
    try self.mArea.MarkLayoutDirty(engine_context);
    if (built_from.len == 0) return;

    const grid = try Widgets.Grid(engine_context, .{ .Entity = self.mArea }, TILE_GAP);
    self.mGrid = grid;
    if (self.mPath.items.len > self.mRoot.items.len) try self.AddTile(engine_context, grid, .Back, "Back");
    for (listing) |listed| try self.AddTile(engine_context, grid, listed.Kind, listed.Name);
}

fn AddTile(self: *ContentBrowserPanel, engine_context: *EngineContext, grid: Entity, kind: Kind, name: []const u8) !void {
    const engine_allocator = engine_context.EngineAllocator();
    const shown = try ShortName(engine_context.FrameAllocator(), name);
    const tile = try Widgets.Tile(engine_context, .{ .Entity = grid }, self.mIcons.Of(kind), shown, TILE_WIDTH);
    switch (kind) {
        .Back, .Folder => {},
        //a file can be dragged, carrying which file it is
        .Texture, .Object, .Script, .Audio, .Font => {
            _ = try tile.AddComponent(engine_context, DragSourceComponent{});
            _ = try tile.AddComponent(engine_context, try FileRefComponent.Init(engine_context, try self.RelPath(engine_context.FrameAllocator(), name), .Prj));
        },
    }
    try self.mTiles.append(engine_allocator, .{ .Entity = tile, .Kind = kind, .NameStart = self.mNames.items.len, .NameLen = name.len });
    try self.mNames.appendSlice(engine_allocator, name);
}

/// `name`, shortened to MAX_NAME_LEN letters ending in "..." if it is longer. Counted in letters, not bytes
fn ShortName(frame_allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    const letters = std.unicode.utf8CountCodepoints(name) catch return name;
    if (letters <= MAX_NAME_LEN) return name;
    var view = std.unicode.Utf8View.initUnchecked(name).iterator();
    var kept: usize = 0;
    for (0..MAX_NAME_LEN - 3) |_| kept += (view.nextCodepointSlice() orelse break).len;
    return try std.fmt.allocPrint(frame_allocator, "{s}...", .{name[0..kept]});
}

fn Same(a: Entity, b: Entity) bool {
    return a.mID == b.mID and a.mManager == b.mManager;
}

/// Puts `text` on a line, folded away while it says nothing
fn ShowLine(engine_context: *EngineContext, line: Entity, text: []const u8) !void {
    try WidgetActions.SetText(engine_context, line, text);
    const item = line.GetComponent(LayoutItemComponent).?;
    const hidden = text.len == 0;
    if (item.mCollapsed == hidden) return;
    item.mCollapsed = hidden;
    try line.MarkLayoutDirty(engine_context);
}
