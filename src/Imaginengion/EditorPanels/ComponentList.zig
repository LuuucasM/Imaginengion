//! An object's components as the editor's own UI shows them, for a panel to put in itself: a folding header for each
//! component the object has, in the list's order, with the rows its UIRender asks for under it (a component without a
//! UIRender has an empty header, so it can still be seen and deleted). Right clicking a header offers to delete that
//! component, and right clicking the panel (the menu target the panel hands in) offers to add one the object doesn't
//! have. The menus' clicks come in through the editor's pointer events (ActionOf), and Run does what was picked.
//! Built once for an object: the panel builds it again when the object or which components it has change, or when a
//! field asks for it (BindingSystem.TakeRebuild with Root).
const std = @import("std");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const UIElement = @import("../ECSObjects/UIElement.zig");
const Widgets = @import("../UI/Widgets.zig");
const Inspector = @import("../UI/Inspector.zig");

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const LayoutComponent = EntityComponents.LayoutComponent;
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const ShapeGeometry = @import("../Renderer/ShapeGeometry.zig");
const ClipComponent = EntityComponents.ClipComponent;
const SurfaceComponent = EntityComponents.SurfaceComponent;
const AttribComponent = EntityComponents.AttribComponent;
const UIComponents = @import("../ECSComponents/UIComponents.zig");

/// The list for objects of type ObjectType, showing the components in `components`
pub fn ComponentList(comptime ObjectType: type, comptime components: []const type) type {
    return struct {
        const Self = @This();

        /// Which of the components an object has
        pub const Present = std.StaticBitSet(components.len);

        /// What a menu item does: add or delete the component at that place in the list
        pub const Action = union(enum) {
            Add: usize,
            Delete: usize,
        };

        const ItemAction = struct {
            Item: Entity,
            Action: Action,
        };

        mObject: ObjectType = undefined,
        /// The column of headers, null while nothing is built. What a field that asks to be built again names
        mRoot: ?Entity = null,
        /// The right-click menus it made, each a popup at the top of its scene
        mMenus: std.ArrayList(Entity) = .empty,
        /// What each of the menus' items does
        mItems: std.ArrayList(ItemAction) = .empty,

        pub fn Deinit(self: *Self, engine_allocator: std.mem.Allocator) void {
            self.mMenus.deinit(engine_allocator);
            self.mItems.deinit(engine_allocator);
        }

        pub fn PresentOf(object: ObjectType) Present {
            var present: Present = .empty;
            inline for (components, 0..) |component_type, i| {
                if (object.HasComponent(component_type)) present.set(i);
            }
            return present;
        }

        /// Builds the list for `object` in `parent`, in place of the one there was. Right clicking `menu_target`
        /// opens the menu to add a component
        pub fn Build(self: *Self, engine_context: *EngineContext, parent: Entity, menu_target: Entity, object: ObjectType, options: Widgets.Options) !void {
            const zone = Tracy.ZoneInit("ComponentList::Build", @src());
            defer zone.Deinit();
            try self.Clear(engine_context);
            const engine_allocator = engine_context.EngineAllocator();
            self.mObject = object;

            const root = try Widgets.Column(engine_context, .{ .Entity = parent });
            self.mRoot = root;
            inline for (components, 0..) |component_type, i| {
                if (object.HasComponent(component_type)) {
                    const section = try Widgets.CollapsingHeader(engine_context, .{ .Entity = root }, component_type.Name, true, options);
                    if (comptime @hasDecl(component_type, "UIRender")) {
                        try Inspector.RenderComponent(engine_context, section.Content.?, root, object, component_type, options);
                    }
                    if (comptime IsRemovable(component_type)) {
                        const menu = try Widgets.ContextMenu(engine_context, section.Header, options);
                        try self.mMenus.append(engine_allocator, menu);
                        try self.AddItem(engine_context, menu, "Delete Component", .{ .Delete = i }, options);
                    }
                }
            }

            //what can be added: only made when there is something, so a right click with nothing to add opens nothing
            var addable: usize = 0;
            inline for (components) |component_type| {
                if (comptime IsAddable(component_type)) {
                    if (!object.HasComponent(component_type)) addable += 1;
                }
            }
            if (addable == 0) return;
            const add_menu = try Widgets.ContextMenu(engine_context, menu_target, options);
            try self.mMenus.append(engine_allocator, add_menu);
            inline for (components, 0..) |component_type, i| {
                if (comptime IsAddable(component_type)) {
                    if (!object.HasComponent(component_type)) try self.AddItem(engine_context, add_menu, component_type.Name, .{ .Add = i }, options);
                }
            }
        }

        /// Takes the list and its menus away: hidden now, deleted at the end of the frame
        pub fn Clear(self: *Self, engine_context: *EngineContext) !void {
            if (self.mRoot) |root| try Remove(engine_context, root);
            for (self.mMenus.items) |menu| try Remove(engine_context, menu);
            self.mRoot = null;
            self.mMenus.clearRetainingCapacity();
            self.mItems.clearRetainingCapacity();
        }

        /// What clicking `item` does, null if it isn't one of the list's menu items
        pub fn ActionOf(self: *const Self, item: Entity) ?Action {
            for (self.mItems.items) |entry| {
                if (entry.Item.mID == item.mID and entry.Item.mManager == item.mManager) return entry.Action;
            }
            return null;
        }

        /// Does what a menu item asked for, to the object the list was built for
        pub fn Run(self: *const Self, engine_context: *EngineContext, action: Action) !void {
            inline for (components, 0..) |component_type, i| {
                switch (action) {
                    .Add => |index| if (index == i) try AddFromPanel(component_type, engine_context, self.mObject),
                    .Delete => |index| if (index == i) try self.mObject.RemoveComponent(engine_context, component_type),
                }
            }
        }

        fn AddItem(self: *Self, engine_context: *EngineContext, menu: Entity, text: []const u8, action: Action, options: Widgets.Options) !void {
            const item = try Widgets.MenuItem(engine_context, menu, text, .{ .StockScripts = options.StockScripts });
            try self.mItems.append(engine_context.EngineAllocator(), .{ .Item = item, .Action = action });
        }
    };
}

/// Hides an entity until it is deleted at the end of the frame
fn Remove(engine_context: *EngineContext, entity: Entity) !void {
    if (!entity.IsActive()) return;
    if (entity.GetComponent(LayoutItemComponent)) |item| item.mCollapsed = true;
    try entity.MarkLayoutDirty(engine_context);
    try entity.Delete(engine_context);
}

/// A component the object can't work without declares `Removable = false`, and is offered no delete
fn IsRemovable(comptime component_type: type) bool {
    return !@hasDecl(component_type, "Removable") or component_type.Removable;
}

/// A component that only makes sense set up by the engine declares `Addable = false`, and is shown but never offered
fn IsAddable(comptime component_type: type) bool {
    return !@hasDecl(component_type, "Addable") or component_type.Addable;
}

/// Adds a component the way picking it from a panel's menu does: at its defaults, except that adding layout to
/// something with a quad keeps the quad the size it is. A layout item starts at the quad's size, fixed, and a
/// container with no item gets one like that. Fitting would shrink the quad to nothing, since layout only ever sizes
/// a quad (it's the element's background), and never fits to one. A shape or text comes with a surface if the entity
/// has none, so it shows up. Code, files and templates add exactly what they're given instead: a saved Fit is a real
/// choice, and can't be told apart from a default one
pub fn AddFromPanel(comptime component_type: type, engine_context: *EngineContext, object: anytype) !void {
    if (comptime @TypeOf(object) == Entity and (component_type == LayoutItemComponent or component_type == LayoutComponent)) {
        if (ShapeGeometry.QuadOf(object)) |quad| {
            const keeps_size = LayoutItemComponent{ .mWidth = .{ .Fixed = quad.Size.x }, .mHeight = .{ .Fixed = quad.Size.y } };
            if (component_type == LayoutItemComponent) {
                _ = try object.AddComponent(engine_context, keeps_size);
                return;
            }
            _ = try object.AddComponent(engine_context, LayoutComponent{});
            if (!object.HasComponent(LayoutItemComponent)) _ = try object.AddComponent(engine_context, keeps_size);
            return;
        }
    }
    _ = try object.AddComponent(engine_context, component_type{});
    if (comptime @TypeOf(object) == Entity and (component_type == EntityComponents.ShapeComponent or component_type == EntityComponents.TextComponent)) {
        if (!object.HasComponent(SurfaceComponent)) _ = try object.AddComponent(engine_context, SurfaceComponent{});
    }
    //what a UI component needs of its entity, given the way picking it from the entity's menu would give it: a popup
    //opens and closes through the entity's layout item, a scroll cuts off what runs past with the entity's clip, and a
    //number field shows the entity's attribute, a float to start with
    if (comptime @TypeOf(object) == UIElement) {
        const owner = object.GetOwner();
        if (owner.IsActive()) {
            if (comptime component_type == UIComponents.PopupComponent) {
                if (!owner.HasComponent(LayoutItemComponent)) try AddFromPanel(LayoutItemComponent, engine_context, owner);
            }
            if (comptime component_type == UIComponents.ScrollComponent) {
                if (!owner.HasComponent(ClipComponent)) _ = try owner.AddComponent(engine_context, ClipComponent{});
            }
            if (comptime component_type == UIComponents.NumberFieldComponent) {
                if (!owner.HasComponent(AttribComponent)) _ = try owner.AddComponent(engine_context, AttribComponent{ .mData = .{ .float32 = 0 } });
            }
        }
    }
}
