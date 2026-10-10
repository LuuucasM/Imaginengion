//! The Scripts panel, in the editor's own UI, in the shell's Scripts tab: the selected object's name, then a row for
//! each of its scripts, which right clicking offers to delete. A line says why when there is nothing to list. Every
//! frame the selection and its scripts are checked against what the rows were built for, and they are built again when
//! they differ. A script is added by dropping it on the panel from the Content Browser: an entity script onto an
//! entity, a scene script onto a scene. Players and game modes have no scripts yet
const std = @import("std");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const Widgets = @import("../UI/Widgets.zig");
const WidgetActions = @import("../UI/WidgetActions.zig");
const UIManager = @import("../UI/UIManager.zig");
const EntityComponents = @import("../ECSComponents/EComponents.zig");
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const SurfaceComponent = EntityComponents.SurfaceComponent;
const DropTargetComponent = EntityComponents.DropTargetComponent;
const FileRefComponent = EntityComponents.FileRefComponent;
const ScriptAsset = @import("../ECSComponents/AComponents.zig").ScriptAsset;
const ScriptType = @import("../ECSComponents/Asset/ScriptAsset.zig").ScriptType;
const PointerDroppedEvent = @import("../Events/PointerEventData.zig").PointerDroppedEvent;
const SelectedObject = @import("../Programs/EditorProgram.zig").SelectedObject;

const ScriptsPanel = @This();

/// What a script row's menu item does: delete that script
const ItemAction = struct {
    Item: Entity,
    Script: SelectedObject,
};

/// The panel's content, in the Scripts tab
mArea: Entity = .uninit,
/// The selected object's name, folded away when nothing is selected
mTitle: Entity = .uninit,
/// Why there is nothing to list, folded away when there is
mMessage: Entity = .uninit,
/// The column of script rows, null while none is built
mRows: ?Entity = null,
/// The rows' right-click menus, each a popup at the top of the scene
mMenus: std.ArrayList(Entity) = .empty,
mItems: std.ArrayList(ItemAction) = .empty,
/// The object the rows were built for, and its scripts then
mBuiltFor: ?SelectedObject = null,
mBuiltScripts: std.ArrayList(SelectedObject) = .empty,
mOptions: Widgets.Options = .{},

/// Builds the panel into `page`, the shell's Scripts tab
pub fn Build(engine_context: *EngineContext, page: Entity, options: Widgets.Options) !ScriptsPanel {
    const zone = Tracy.ZoneInit("ScriptsPanel::Build", @src());
    defer zone.Deinit();
    const area = try Widgets.ScrollArea(engine_context, .{ .Entity = page });
    //a background, so dropping on the empty part of the panel lands on it, and it takes files (a script is checked for
    //when it is dropped)
    _ = try area.AddComponent(engine_context, SurfaceComponent{});
    try UIManager.Style(engine_context, area, "Window");
    _ = try area.AddComponent(engine_context, DropTargetComponent.Accepting(&.{FileRefComponent}));
    return .{
        .mArea = area,
        .mTitle = try Widgets.Label(engine_context, .{ .Entity = area }, ""),
        .mMessage = try Widgets.Label(engine_context, .{ .Entity = area }, ""),
        .mOptions = options,
    };
}

pub fn Deinit(self: *ScriptsPanel, engine_allocator: std.mem.Allocator) void {
    self.mMenus.deinit(engine_allocator);
    self.mItems.deinit(engine_allocator);
    self.mBuiltScripts.deinit(engine_allocator);
}

/// Whether it is shown in its tab (the Window menu's Scripts)
pub fn IsOpen(self: ScriptsPanel) bool {
    return !self.mArea.GetComponent(LayoutItemComponent).?.mCollapsed;
}

pub fn Toggle(self: ScriptsPanel, engine_context: *EngineContext) !void {
    const item = self.mArea.GetComponent(LayoutItemComponent).?;
    item.mCollapsed = !item.mCollapsed;
    try self.mArea.MarkLayoutDirty(engine_context);
}

/// Once a frame, before layout, while it is shown: the rows built again if the selection or its scripts changed, and
/// the lines above them
pub fn Update(self: *ScriptsPanel, engine_context: *EngineContext, selected: ?SelectedObject) !void {
    const zone = Tracy.ZoneInit("ScriptsPanel::Update", @src());
    defer zone.Deinit();
    if (!self.IsOpen()) return;

    const frame_allocator = engine_context.FrameAllocator();
    var title: []const u8 = "";
    var message: []const u8 = "";
    var scripts: std.ArrayList(SelectedObject) = .empty;
    var listed: ?SelectedObject = null;
    if (selected) |object| {
        if (IsActive(object)) {
            title = NameOf(object);
            switch (object) {
                .player => message = "Players can't have scripts yet",
                .gamecontext => message = "Game modes can't have scripts yet",
                .entity, .scene_layer => {
                    listed = object;
                    try ScriptsOf(frame_allocator, object, &scripts);
                    if (scripts.items.len == 0) message = "No scripts yet";
                },
            }
        }
    } else {
        message = "Select an object to see its scripts";
    }

    if (!self.IsBuiltFor(listed, scripts.items)) try self.Rebuild(engine_context, listed, scripts.items);
    try ShowLine(engine_context, self.mTitle, title);
    try ShowLine(engine_context, self.mMessage, message);
}

/// What clicking `item` does: the script to delete, null if it isn't one of the panel's menu items
pub fn ActionOf(self: *const ScriptsPanel, item: Entity) ?SelectedObject {
    for (self.mItems.items) |entry| {
        if (Same(entry.Item, item)) return entry.Script;
    }
    return null;
}

/// Deletes a script, at the end of the frame. The rows are built again the next frame, seeing it has gone
pub fn Run(engine_context: *EngineContext, script: SelectedObject) !void {
    switch (script) {
        inline else => |object| try object.Delete(engine_context),
    }
}

/// Which kind of object a script goes on, from its type: null for one that goes on neither an entity nor a scene
pub fn ScriptOwnerOf(script_type: ScriptType) ?std.meta.Tag(SelectedObject) {
    const name = @tagName(script_type);
    if (std.mem.startsWith(u8, name, "Entity")) return .entity;
    if (std.mem.startsWith(u8, name, "Scene")) return .scene_layer;
    return null;
}

/// A drop on the panel: a script added to the selected object, if it is the kind of script that object takes
pub fn OnDrop(self: ScriptsPanel, engine_context: *EngineContext, on: Entity, dropped: PointerDroppedEvent, selected: ?SelectedObject) !void {
    if (!Same(on, self.mArea)) return;
    const file_ref = dropped.mSource.GetComponent(FileRefComponent) orelse return;
    const rel_path = file_ref.mRelPath.items;
    if (!std.mem.eql(u8, std.fs.path.extension(rel_path), ".zig")) {
        std.log.warn("Only a script (.zig) can be dropped on the Scripts panel, not {s}", .{rel_path});
        return;
    }
    const object = selected orelse return;
    if (!IsActive(object)) return;

    //loading it (compiling it if it hasn't been) to find out what it is a script for
    var script_handle = try engine_context.mAssetManager.GetAssetHandle(engine_context, .{ .File = .{ .rel_path = rel_path, .path_type = file_ref.mPathType } });
    defer script_handle.ReleaseAsset();
    const script_type = (try script_handle.GetAsset(engine_context, ScriptAsset)).GetScriptType();
    if (ScriptOwnerOf(script_type) != std.meta.activeTag(object)) {
        std.log.warn("{s} is a {s} script, which doesn't go on a {s}", .{ rel_path, @tagName(script_type), @tagName(object) });
        return;
    }
    switch (object) {
        .entity => |entity| try entity.AddComponentScript(engine_context, rel_path, file_ref.mPathType),
        .scene_layer => |scene| try scene.AddComponentScript(engine_context, rel_path, file_ref.mPathType),
        .player, .gamecontext => {},
    }
}

fn IsBuiltFor(self: ScriptsPanel, listed: ?SelectedObject, scripts: []const SelectedObject) bool {
    if ((listed == null) != (self.mBuiltFor == null)) return false;
    if (listed) |object| {
        if (!SameObject(object, self.mBuiltFor.?)) return false;
    }
    if (scripts.len != self.mBuiltScripts.items.len) return false;
    for (scripts, self.mBuiltScripts.items) |script, built| {
        if (!SameObject(script, built)) return false;
    }
    return true;
}

/// The old rows hidden and deleted, and new ones built for `scripts`
fn Rebuild(self: *ScriptsPanel, engine_context: *EngineContext, listed: ?SelectedObject, scripts: []const SelectedObject) !void {
    const zone = Tracy.ZoneInit("ScriptsPanel::Rebuild", @src());
    defer zone.Deinit();
    const engine_allocator = engine_context.EngineAllocator();
    //each row's menu goes with it
    if (self.mRows) |rows| try Widgets.Remove(engine_context, rows, &.{});
    self.mRows = null;
    self.mMenus.clearRetainingCapacity();
    self.mItems.clearRetainingCapacity();
    self.mBuiltScripts.clearRetainingCapacity();
    try self.mBuiltScripts.appendSlice(engine_allocator, scripts);
    self.mBuiltFor = listed;
    try self.mArea.MarkLayoutDirty(engine_context);
    if (scripts.len == 0) return;

    const rows = try Widgets.Column(engine_context, .{ .Entity = self.mArea });
    self.mRows = rows;
    for (scripts) |script| {
        //a plain row: it only has its menu, clicking it does nothing
        const row = try Widgets.SelectableRow(engine_context, .{ .Entity = rows }, NameOf(script), .{ .StockScripts = false });
        const menu = try Widgets.ContextMenu(engine_context, row, self.mOptions);
        try self.mMenus.append(engine_allocator, menu);
        const item = try Widgets.MenuItem(engine_context, menu, "Delete Script", .{ .StockScripts = self.mOptions.StockScripts });
        try self.mItems.append(engine_allocator, .{ .Item = item, .Script = script });
    }
}

/// An entity's or scene's scripts, in order
fn ScriptsOf(frame_allocator: std.mem.Allocator, object: SelectedObject, scripts: *std.ArrayList(SelectedObject)) !void {
    switch (object) {
        inline else => |typed, tag| {
            var iter = typed.GetIterator(.Script);
            while (iter.next()) |script| try scripts.append(frame_allocator, @unionInit(SelectedObject, @tagName(tag), script));
        },
    }
}

fn IsActive(object: SelectedObject) bool {
    return switch (object) {
        inline else => |typed| typed.IsActive(),
    };
}

/// An object's name, up to the first 0 if it was saved with one
fn NameOf(object: SelectedObject) []const u8 {
    const name = switch (object) {
        inline else => |typed| typed.GetName(),
    };
    return name[0 .. std.mem.indexOfScalar(u8, name, 0) orelse name.len];
}

fn SameObject(a: SelectedObject, b: SelectedObject) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        inline else => |typed, tag| typed.mID == @field(b, @tagName(tag)).mID and typed.mManager == @field(b, @tagName(tag)).mManager,
    };
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
