//! A hierarchy panel, in the editor's own UI, in one of the shell's hierarchy tabs: a tree of the world's objects of one
//! type (entities, scenes, players or game modes), the top level ones with what is under each nested below it. Scenes
//! come in stack order, the top layer first. Clicking a row selects its object, and the selected object's row is
//! highlighted however it was selected. Every row can be dragged, carrying its object (ObjectRefComponent). Right
//! clicking a row offers New Child, Make Template, Duplicate and Delete (and New Entity for a scene), right clicking the panel New
//! of its type. Entities and scenes also offer ready-made UI entities (a panel, text, a button, ...), each made by its
//! widget builder (Widgets): the panel's menu puts one in the selected scene, an entity's row under that entity, a
//! scene's row at the top of that scene. An object file of its type dragged from the Content Browser onto the panel is loaded into the world (an
//! entity into the selected scene) and selected. Every frame the world's objects are walked and checked against the shape of the tree that was built
//! (which objects, under which), and it is built again when that changed, keeping which nodes were open; a rename only
//! changes the row's text. Built with BuildForRoots it shows only the objects it is handed each frame and what is under
//! them instead of a whole world, with no menu of its own and no Delete on those top rows: a template's tree, in a
//! template edit window
const std = @import("std");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const WorldManager = @import("../Core/WorldManager.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const Player = @import("../ECSObjects/Player.zig");
const GameContext = @import("../ECSObjects/GameContext.zig");
const UIManager = @import("../UI/UIManager.zig");
const Widgets = @import("../UI/Widgets.zig");
const StyleSystem = @import("../UI/StyleSystem.zig");
const WidgetActions = @import("../UI/WidgetActions.zig");
const GroupQuery = @import("../ECS/ECSManager.zig").GroupQuery;
const EntityTagComponent = @import("../ECS/Components.zig").EntityTagComponent;
const SelectedObject = @import("../Programs/EditorProgram.zig").SelectedObject;
const Serializer = @import("../Serializer/Serializer.zig");
const PointerDroppedEvent = @import("../Events/PointerEventData.zig").PointerDroppedEvent;
const MathTypes = @import("../Math/MathTypes.zig");

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const LayoutComponent = EntityComponents.LayoutComponent;
const TextComponent = EntityComponents.TextComponent;
const SurfaceComponent = EntityComponents.SurfaceComponent;
const SelectedTag = EntityComponents.SelectedTag;
const DragSourceComponent = EntityComponents.DragSourceComponent;
const DropTargetComponent = EntityComponents.DropTargetComponent;
const FileRefComponent = EntityComponents.FileRefComponent;
const ObjectRefComponent = EntityComponents.ObjectRefComponent;
const NameComponent = EntityComponents.NameComponent;
const TmplRefComponent = EntityComponents.TmplRefComponent;
const StackPosComponent = @import("../ECSComponents/SComponents.zig").StackPosComponent;

/// The ready-made UI entities the entity and scene menus offer, each one widget builder's
pub const UIKind = enum {
    Panel,
    Text,
    Button,
    Checkbox,
    TextField,

    /// Its menu item's text, and the name of what it makes
    pub fn Name(self: UIKind) []const u8 {
        return switch (self) {
            .Panel => "Panel",
            .Text => "Text",
            .Button => "Button",
            .Checkbox => "Checkbox",
            .TextField => "Text Field",
        };
    }
};

/// A new Panel's size
const UI_PANEL_SIZE = MathTypes.Vec2(f32){ .x = 200, .y = 150 };
/// The width a ready-made UI entity that fills what it is in gets when it isn't in a layout, where there is nothing to
/// fill (in an overlay it would be the whole screen). In overlay units, like the rest of a widget's sizes
const UI_TOP_WIDTH: f32 = 200;

/// The panel for objects of type T
pub fn HierarchyPanel(comptime T: type) type {
    const ECSManagerT = WorldManager.ManagerT(T).ECSManagerT;
    const ChildComponent = ECSManagerT.ChildComponent;
    const EntityTagQuery = GroupQuery{ .Component = EntityTagComponent };
    const ChildQuery = GroupQuery{ .Component = ChildComponent };

    return struct {
        const Self = @This();

        /// Top level objects: tagged as real objects, minus anything that is someone's child
        const ROOT_QUERY = GroupQuery{ .Not = .{ .mFirst = &EntityTagQuery, .mSecond = &ChildQuery } };

        /// What a click on the panel does
        pub const Action = union(enum) {
            /// a row clicked: its object selected
            Select: T,
            /// from a row's menu, for the object it was opened on
            NewChild,
            NewEntity,
            MakeTemplate,
            Duplicate,
            Delete,
            /// a ready-made UI entity under the entity, or at the top of the scene, it was opened on
            NewUIChild: UIKind,
            /// from the panel's menu
            New,
            NewOverlay,
            /// a ready-made UI entity in the selected scene
            NewUI: UIKind,
        };

        const MenuItem = struct {
            Item: Entity,
            Action: Action,
        };

        const Row = struct {
            Header: Entity,
            Label: Entity,
            /// what folds away under a node, null for a leaf
            Content: ?Entity,
            Object: T,
            /// 0 for a top row
            Depth: u32,
        };

        /// A whole world's objects, or only what it is handed (BuildForRoots)
        const Mode = enum { World, Roots };

        mArea: Entity = .uninit,
        /// The tree, null while none is built
        mTree: ?Entity = null,
        mRows: std.ArrayList(Row) = .empty,
        /// The world and the tree's shape (each object's id and depth, in order) as they were when it was built
        mBuiltWorld: ?*WorldManager = null,
        mBuiltShape: std.ArrayList(u64) = .empty,
        /// Which objects' nodes were open, kept across building the tree again
        mOpen: std.AutoHashMapUnmanaged(T.Type, void) = .empty,
        /// The menu every row opens, and its items, and the object it was last opened on
        mRowMenu: Entity = .uninit,
        mRowItems: std.ArrayList(MenuItem) = .empty,
        mMenuObject: ?T = null,
        /// The panel's own menu's items
        mAreaItems: std.ArrayList(MenuItem) = .empty,
        mMode: Mode = .World,
        mOptions: Widgets.Options = .{},

        /// Builds the panel into `page`, one of the shell's hierarchy tabs: a whole world's objects
        pub fn Build(engine_context: *EngineContext, page: Entity, options: Widgets.Options) !Self {
            var self = try Make(engine_context, page, options, .World);
            try self.AddAreaMenu(engine_context);
            //it takes files (one of its type is checked for when it is dropped)
            _ = try self.mArea.AddComponent(engine_context, DropTargetComponent.Accepting(&.{FileRefComponent}));
            return self;
        }

        /// Builds a tree of only the objects UpdateRoots hands it, into `page`
        pub fn BuildForRoots(engine_context: *EngineContext, page: Entity, options: Widgets.Options) !Self {
            return try Make(engine_context, page, options, .Roots);
        }

        fn Make(engine_context: *EngineContext, page: Entity, options: Widgets.Options, mode: Mode) !Self {
            const zone = Tracy.ZoneInit("HierarchyPanel::Build", @src());
            defer zone.Deinit();
            var self = Self{ .mOptions = options, .mMode = mode };
            self.mArea = try Widgets.ScrollArea(engine_context, .{ .Entity = page });
            //a background, so a right click on the empty part of the panel opens its menu
            _ = try self.mArea.AddComponent(engine_context, SurfaceComponent{});
            try UIManager.Style(engine_context, self.mArea, "Window");

            //one menu for every row, made once: its items act on the row it was opened on
            self.mRowMenu = try Widgets.NewContextMenu(engine_context, self.mArea);
            const type_name = TypeName();
            try self.AddRowItem(engine_context, try std.fmt.allocPrint(engine_context.FrameAllocator(), "New Child {s}", .{type_name}), .NewChild);
            if (T == Scene) try self.AddRowItem(engine_context, "New Entity", .NewEntity);
            if (T == Entity or T == Scene) {
                const ui_menu = try Widgets.Submenu(engine_context, self.mRowMenu, if (T == Entity) "New UI Child" else "New UI Entity", self.mOptions);
                for (std.enums.values(UIKind)) |kind| {
                    try self.AddItem(engine_context, ui_menu, &self.mRowItems, kind.Name(), .{ .NewUIChild = kind });
                }
            }
            try self.AddRowItem(engine_context, "Make Template", .MakeTemplate);
            try self.AddRowItem(engine_context, try std.fmt.allocPrint(engine_context.FrameAllocator(), "Duplicate {s}", .{type_name}), .Duplicate);
            try self.AddRowItem(engine_context, try std.fmt.allocPrint(engine_context.FrameAllocator(), "Delete {s}", .{type_name}), .Delete);
            return self;
        }

        /// The panel's own menu, New of its type, on its empty space
        fn AddAreaMenu(self: *Self, engine_context: *EngineContext) !void {
            const engine_allocator = engine_context.EngineAllocator();
            const item_options = Widgets.MenuItemOptions{ .StockScripts = self.mOptions.StockScripts };
            const area_menu = try Widgets.ContextMenu(engine_context, self.mArea, self.mOptions);
            switch (T) {
                Entity => {
                    try self.mAreaItems.append(engine_allocator, .{ .Item = try Widgets.MenuItem(engine_context, area_menu, "New Entity", item_options), .Action = .New });
                    const ui_menu = try Widgets.Submenu(engine_context, area_menu, "New UI Entity", self.mOptions);
                    for (std.enums.values(UIKind)) |kind| {
                        try self.AddItem(engine_context, ui_menu, &self.mAreaItems, kind.Name(), .{ .NewUI = kind });
                    }
                },
                Scene => {
                    try self.mAreaItems.append(engine_allocator, .{ .Item = try Widgets.MenuItem(engine_context, area_menu, "New Game Scene", item_options), .Action = .New });
                    try self.mAreaItems.append(engine_allocator, .{ .Item = try Widgets.MenuItem(engine_context, area_menu, "New Overlay Scene", item_options), .Action = .NewOverlay });
                },
                Player => try self.mAreaItems.append(engine_allocator, .{ .Item = try Widgets.MenuItem(engine_context, area_menu, "New Player", item_options), .Action = .New }),
                GameContext => try self.mAreaItems.append(engine_allocator, .{ .Item = try Widgets.MenuItem(engine_context, area_menu, "New Game Mode", item_options), .Action = .New }),
                else => @compileError("Not an object type: " ++ @typeName(T)),
            }
        }

        pub fn Deinit(self: *Self, engine_allocator: std.mem.Allocator) void {
            self.mRows.deinit(engine_allocator);
            self.mBuiltShape.deinit(engine_allocator);
            self.mOpen.deinit(engine_allocator);
            self.mRowItems.deinit(engine_allocator);
            self.mAreaItems.deinit(engine_allocator);
        }

        /// Once a frame, before layout: `world`'s tree built again if its shape changed, each row named after its
        /// object, the selected object's row highlighted, and the panel's menu's items greyed out when they can't be
        /// done (New Entity and the New UI Entity ones need a scene selected)
        pub fn Update(self: *Self, engine_context: *EngineContext, world: *WorldManager, selected: ?SelectedObject) !void {
            const zone = Tracy.ZoneInit("HierarchyPanel::Update", @src());
            defer zone.Deinit();
            const frame_allocator = engine_context.FrameAllocator();

            var objects: std.ArrayList(T) = .empty;
            var shape: std.ArrayList(u64) = .empty;
            try Walk(frame_allocator, world, &objects, &shape);
            try self.Sync(engine_context, world, objects.items, shape.items, selected);
            if (T == Entity) {
                const has_scene = if (selected) |object| object == .scene_layer and object.scene_layer.IsActive() else false;
                for (self.mAreaItems.items) |item| try WidgetActions.SetDisabled(engine_context, item.Item, !has_scene);
            }
        }

        /// Once a frame, for a tree built with BuildForRoots: `roots` and what is under them, in that order, the tree built
        /// again if that changed, and the selected object's row highlighted
        pub fn UpdateRoots(self: *Self, engine_context: *EngineContext, roots: []const T, selected: ?SelectedObject) !void {
            const zone = Tracy.ZoneInit("HierarchyPanel::UpdateRoots", @src());
            defer zone.Deinit();
            const frame_allocator = engine_context.FrameAllocator();
            var objects: std.ArrayList(T) = .empty;
            var shape: std.ArrayList(u64) = .empty;
            for (roots) |root| {
                if (root.IsActive()) try Visit(frame_allocator, root, 0, &objects, &shape);
            }
            try self.Sync(engine_context, null, objects.items, shape.items, selected);
        }

        /// The tree built again if its shape changed, each row named after its object, and the selection highlighted
        fn Sync(self: *Self, engine_context: *EngineContext, world: ?*WorldManager, objects: []const T, shape: []const u64, selected: ?SelectedObject) !void {
            if (self.mBuiltWorld != world or !std.mem.eql(u64, shape, self.mBuiltShape.items) or self.mTree == null) {
                try self.Rebuild(engine_context, world, objects, shape);
            }
            for (self.mRows.items) |row| try WidgetActions.SetText(engine_context, row.Label, NameOf(row.Object));
            try self.ShowSelected(engine_context, selected);
        }

        /// What a left click on `entity` does: a row selects its object, a menu item does its action. Null for anything
        /// else
        pub fn ActionOf(self: *const Self, entity: Entity) ?Action {
            for (self.mRows.items) |row| {
                if (Same(row.Header, entity)) return .{ .Select = row.Object };
            }
            for ([_][]const MenuItem{ self.mRowItems.items, self.mAreaItems.items }) |items| {
                for (items) |item| {
                    if (Same(item.Item, entity)) return item.Action;
                }
            }
            return null;
        }

        /// A right click on `entity`: on a row, the row menu is about to open for its object, and its items are greyed
        /// out for what can't be done to it (Make Template with no project open, or for a copy of a template)
        pub fn OnRightClick(self: *Self, engine_context: *EngineContext, entity: Entity) !void {
            for (self.mRows.items) |row| {
                if (!Same(row.Header, entity)) continue;
                self.mMenuObject = row.Object;
                const can_make_template = engine_context.mProject.IsOpen() and !row.Object.HasComponent(TmplRefComponent);
                //a template's own root can't go, or have a copy next to it: the template is it
                const can_delete = self.mMode == .World or row.Depth > 0;
                for (self.mRowItems.items) |item| {
                    if (item.Action == .MakeTemplate) try WidgetActions.SetDisabled(engine_context, item.Item, !can_make_template);
                    if (item.Action == .Delete or item.Action == .Duplicate) try WidgetActions.SetDisabled(engine_context, item.Item, !can_delete);
                }
                return;
            }
        }

        /// Does what a click asked for, in `world`. Select changes the editor's selection, and so does Duplicate, to the copy
        pub fn Run(self: *const Self, engine_context: *EngineContext, action: Action, world: *WorldManager, selected: *?SelectedObject) !void {
            const engine_allocator = engine_context.EngineAllocator();
            switch (action) {
                .Select => |object| selected.* = ToSelected(object),
                .New => switch (T) {
                    Entity => if (selected.*) |object| {
                        if (object == .scene_layer) _ = try object.scene_layer.CreateEntity(engine_context, Entity.DefaultConfig);
                    },
                    Scene => _ = try world.NewScene(engine_context, .GameLayer, Scene.DefaultConfig),
                    Player => _ = try world.CreatePlayer(engine_context, Player.DefaultConfig),
                    GameContext => _ = try world.CreateGameContext(engine_context, GameContext.DefaultConfig),
                    else => unreachable,
                },
                .NewOverlay => if (T == Scene) {
                    _ = try world.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
                },
                .NewUI => |kind| if (T == Entity) {
                    if (selected.*) |object| {
                        if (object == .scene_layer) _ = try self.NewUIEntity(engine_context, kind, .{ .Scene = object.scene_layer });
                    }
                },
                .NewChild, .NewEntity, .MakeTemplate, .Duplicate, .Delete, .NewUIChild => {
                    const object = self.mMenuObject orelse return;
                    if (!object.IsActive()) return;
                    switch (action) {
                        .NewChild => _ = try object.CreateChild(engine_context, .Entity, T.DefaultConfig),
                        .NewEntity => if (T == Scene) {
                            _ = try object.CreateEntity(engine_context, Entity.DefaultConfig);
                        },
                        .MakeTemplate => try engine_context.mEditorEventManager.Insert(engine_allocator, .EndOfFrame, .{ .MakeTmplEvent = .{ .mObject = ToSelected(object) } }),
                        .Duplicate => selected.* = ToSelected(try object.Duplicate(engine_context)),
                        .Delete => try object.Delete(engine_context),
                        .NewUIChild => |kind| switch (T) {
                            Entity => _ = try self.NewUIEntity(engine_context, kind, .{ .Entity = object }),
                            Scene => _ = try self.NewUIEntity(engine_context, kind, .{ .Scene = object }),
                            else => {},
                        },
                        else => unreachable,
                    }
                },
            }
        }

        /// A drop on the panel: an object file of its type loaded into `world`, as Open Scene does, and selected. An
        /// entity goes into the selected scene, as New Entity does
        pub fn OnDrop(self: *const Self, engine_context: *EngineContext, on: Entity, dropped: PointerDroppedEvent, world: *WorldManager, selected: *?SelectedObject) !void {
            if (!Same(on, self.mArea)) return;
            const file_ref = dropped.mSource.GetComponent(FileRefComponent) orelse return;
            const rel_path = file_ref.mRelPath.items;
            const is_kind = if (Serializer.ObjectKindOf(std.fs.path.extension(rel_path))) |kind| kind == KIND else false;
            if (!is_kind) {
                std.log.warn("Only a {s} file ({s}) can be dropped here, not {s}", .{ TypeName(), std.mem.span(Serializer.FileExtension(T)), rel_path });
                return;
            }
            const object: T = switch (T) {
                Entity => blk: {
                    const scene: ?Scene = if (selected.*) |object| (if (object == .scene_layer and object.scene_layer.IsActive()) object.scene_layer else null) else null;
                    if (scene == null) {
                        std.log.warn("Select a scene to load {s} into", .{rel_path});
                        return;
                    }
                    break :blk try scene.?.LoadEntity(engine_context, rel_path, file_ref.mPathType);
                },
                else => try world.Load(T, engine_context, rel_path, file_ref.mPathType),
            };
            selected.* = ToSelected(object);
        }

        fn AddRowItem(self: *Self, engine_context: *EngineContext, text: []const u8, action: Action) !void {
            try self.AddItem(engine_context, self.mRowMenu, &self.mRowItems, text, action);
        }

        /// An item of `menu` doing `action`, kept in `items`
        fn AddItem(self: *Self, engine_context: *EngineContext, menu: Entity, items: *std.ArrayList(MenuItem), text: []const u8, action: Action) !void {
            const item = try Widgets.MenuItem(engine_context, menu, text, .{ .StockScripts = self.mOptions.StockScripts });
            try items.append(engine_context.EngineAllocator(), .{ .Item = item, .Action = action });
        }

        /// A ready-made UI entity of `kind` under `parent`, named after its kind. It takes the theme's look once and is
        /// then no longer styled, so the colors and font set on it stay. One that starts a layout tree of its own
        /// (not inside a container) gets a width of its own if it fills what it is in. Widgets are built in the
        /// theme's units, so its sizes are turned into the scene's the same way the theme's are: world units in a
        /// game scene, and menu sized in a game's overlay (StyleSystem.ThemeUnit)
        fn NewUIEntity(self: *const Self, engine_context: *EngineContext, kind: UIKind, parent: Widgets.Parent) !Entity {
            const entity = switch (kind) {
                .Panel => try Widgets.Panel(engine_context, parent, UI_PANEL_SIZE),
                .Text => try Widgets.Label(engine_context, parent, "Text"),
                .Button => try Widgets.Button(engine_context, parent, "Button"),
                .Checkbox => try Widgets.Checkbox(engine_context, parent, "Checkbox", self.mOptions),
                .TextField => try Widgets.TextField(engine_context, parent, "Text"),
            };
            try entity.SetName(engine_context, kind.Name());
            //what is inside it named for what it is too: a button's or field's text, a checkbox's box and text
            var children = entity.GetIterator(.Child);
            while (children.next()) |child| try child.SetName(engine_context, if (child.HasComponent(TextComponent)) "Text" else "Box");
            //with no theme to color its box when it is checked, a checkbox shows it with a mark
            if (kind == .Checkbox) try (try Widgets.AddCheckMark(engine_context, entity)).SetName(engine_context, "Check");
            const starts_tree = switch (parent) {
                .Scene => true,
                .Entity => |parent_entity| !parent_entity.HasComponent(LayoutComponent),
            };
            if (starts_tree) {
                const item = entity.GetComponent(LayoutItemComponent).?;
                if (item.mWidth == .Fill) item.mWidth = .{ .Fixed = UI_TOP_WIDTH };
            }
            const unit = StyleSystem.ThemeUnit(entity);
            if (unit != 1) try Widgets.ScaleSizes(engine_context, entity, unit);
            //it starts out looking as the theme has it, and then keeps what is set on it: only the editor follows a theme
            UIManager.StyleOnce(entity);
            return entity;
        }

        /// The world's objects of type T in the order the tree shows them, each before what is under it, and the
        /// tree's shape: each one's id and depth
        fn Walk(frame_allocator: std.mem.Allocator, world: *WorldManager, objects: *std.ArrayList(T), shape: *std.ArrayList(u64)) !void {
            const root_ids = switch (T) {
                Entity => try world.GetEntityGroup(frame_allocator, ROOT_QUERY),
                Scene => try world.GetSceneGroup(frame_allocator, ROOT_QUERY),
                Player => try world.GetPlayerGroup(frame_allocator, ROOT_QUERY),
                GameContext => try world.GetGameContextGroup(frame_allocator, ROOT_QUERY),
                else => unreachable,
            };
            //the top layer first, so the scene that gets events first is the first row
            if (T == Scene) std.sort.insertion(Scene.Type, root_ids.items, world, struct {
                fn Above(w: *WorldManager, a: Scene.Type, b: Scene.Type) bool {
                    return StackPosOf(w, b) < StackPosOf(w, a);
                }
            }.Above);
            for (root_ids.items) |id| try Visit(frame_allocator, ObjectOf(world, id), 0, objects, shape);
        }

        fn Visit(frame_allocator: std.mem.Allocator, object: T, depth: u32, objects: *std.ArrayList(T), shape: *std.ArrayList(u64)) !void {
            try objects.append(frame_allocator, object);
            try shape.append(frame_allocator, (@as(u64, object.mID) << 32) | depth);
            var children = object.GetIterator(.Child);
            while (children.next()) |child| try Visit(frame_allocator, child, depth + 1, objects, shape);
        }

        /// The old tree hidden and deleted, and a new one built for `objects`, its open nodes still open
        fn Rebuild(self: *Self, engine_context: *EngineContext, world: ?*WorldManager, objects: []const T, shape: []const u64) !void {
            const zone = Tracy.ZoneInit("HierarchyPanel::Rebuild", @src());
            defer zone.Deinit();
            const engine_allocator = engine_context.EngineAllocator();
            //which nodes were open, from the tree about to go
            for (self.mRows.items) |row| {
                const content = row.Content orelse continue;
                if (content.GetComponent(LayoutItemComponent).?.mCollapsed) {
                    _ = self.mOpen.remove(row.Object.mID);
                } else {
                    try self.mOpen.put(engine_allocator, row.Object.mID, {});
                }
            }
            //the rows' menus go with them, all but the one they share
            if (self.mTree) |tree| try Widgets.Remove(engine_context, tree, &.{self.mRowMenu});
            self.mRows.clearRetainingCapacity();
            self.mBuiltShape.clearRetainingCapacity();
            try self.mBuiltShape.appendSlice(engine_allocator, shape);
            self.mBuiltWorld = world;

            const tree = try Widgets.Tree(engine_context, .{ .Entity = self.mArea });
            self.mTree = tree;
            //the content each depth's next node goes in: a node's children follow it straight away in the walk
            var parents: std.ArrayList(Entity) = .empty;
            try parents.append(engine_context.FrameAllocator(), tree);
            for (objects, shape, 0..) |object, packed_shape, i| {
                const depth: usize = @intCast(packed_shape & 0xFFFF_FFFF);
                parents.shrinkRetainingCapacity(depth + 1);
                const has_children = i + 1 < shape.len and (shape[i + 1] & 0xFFFF_FFFF) > depth;
                const node = try Widgets.TreeNode(engine_context, .{ .Entity = parents.items[depth] }, NameOf(object), .{
                    .Leaf = !has_children,
                    .Open = self.mOpen.contains(object.mID),
                    .StockScripts = self.mOptions.StockScripts,
                });
                //what dragging the row carries, and the row menu, opened for it
                _ = try node.Header.AddComponent(engine_context, DragSourceComponent{});
                _ = try node.Header.AddComponent(engine_context, ObjectRefComponent{ .mObject = .Of(object) });
                try Widgets.ShareContextMenu(engine_context, node.Header, self.mRowMenu, self.mOptions);
                try self.mRows.append(engine_allocator, .{ .Header = node.Header, .Label = UIManager.LabelOf(node.Header).?, .Content = node.Content, .Object = object, .Depth = @intCast(depth) });
                if (node.Content) |content| try parents.append(engine_context.FrameAllocator(), content);
            }
            try self.mArea.MarkLayoutDirty(engine_context);
        }

        /// The selected object's row highlighted, and no row if it isn't one of this panel's
        fn ShowSelected(self: *Self, engine_context: *EngineContext, selected: ?SelectedObject) !void {
            const target: ?T = if (selected) |object| switch (T) {
                Entity => if (object == .entity) object.entity else null,
                Scene => if (object == .scene_layer) object.scene_layer else null,
                Player => if (object == .player) object.player else null,
                GameContext => if (object == .gamecontext) object.gamecontext else null,
                else => unreachable,
            } else null;
            for (self.mRows.items) |row| {
                const is_target = if (target) |object| object.mID == row.Object.mID else false;
                if (is_target) {
                    try WidgetActions.Select(engine_context, row.Header);
                } else if (row.Header.HasComponent(SelectedTag)) {
                    try row.Header.RemoveComponentSync(engine_context, SelectedTag);
                }
            }
        }

        fn ObjectOf(world: *WorldManager, id: T.Type) T {
            return switch (T) {
                Entity => world.GetEntity(id),
                Scene => world.GetScene(id),
                Player => world.GetPlayer(id),
                GameContext => world.GetGameContext(id),
                else => unreachable,
            };
        }

        /// A scene only gets a stack position through CreateScene, so one that came another way sorts to the bottom
        fn StackPosOf(world: *WorldManager, scene_id: Scene.Type) usize {
            const stack_pos = world.mSManager.GetComponent(StackPosComponent, scene_id) orelse return 0;
            return stack_pos.mPosition;
        }

        /// The kind of object file the panel takes
        const KIND: Serializer.ObjectKind = switch (T) {
            Entity => .Entity,
            Scene => .Scene,
            Player => .Player,
            GameContext => .GameContext,
            else => unreachable,
        };

        fn TypeName() []const u8 {
            return switch (T) {
                Entity => "Entity",
                Scene => "Scene",
                Player => "Player",
                GameContext => "Game Mode",
                else => unreachable,
            };
        }

        fn NameOf(object: T) []const u8 {
            const name = (object.GetComponent(NameComponent) orelse return "Unnamed").mName.items;
            return name[0 .. std.mem.indexOfScalar(u8, name, 0) orelse name.len];
        }

        fn ToSelected(object: T) SelectedObject {
            return switch (T) {
                Entity => .{ .entity = object },
                Scene => .{ .scene_layer = object },
                Player => .{ .player = object },
                GameContext => .{ .gamecontext = object },
                else => unreachable,
            };
        }
    };
}

fn Same(a: Entity, b: Entity) bool {
    return a.mID == b.mID and a.mManager == b.mManager;
}
