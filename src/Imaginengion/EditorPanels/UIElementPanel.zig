//! The UI Element panel, in the editor's own UI: a floating window with the selected entity's UI element, its UI-only
//! components listed and edited like the Components panel lists an entity's own (ComponentList), with a right click
//! on a component to delete it and on the window to add one. A line says why when there is nothing to list. Every
//! frame it is open the selection and which components the element has are checked against what the list was built
//! for, and it is built again when they differ. Opened from the Window menu or an entity's UIElementComponent
const std = @import("std");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const UIElement = @import("../ECSObjects/UIElement.zig");
const UIManager = @import("../UI/UIManager.zig");
const Widgets = @import("../UI/Widgets.zig");
const WidgetActions = @import("../UI/WidgetActions.zig");
const UIComponents = @import("../ECSComponents/UIComponents.zig");
const LayoutItemComponent = @import("../ECSComponents/EComponents.zig").LayoutItemComponent;
const SelectedObject = @import("../Programs/EditorProgram.zig").SelectedObject;
const MathTypes = @import("../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;

const UIElementPanel = @This();

pub const Components = @import("ComponentList.zig").ComponentList(UIElement, &UIComponents.ComponentsPanelList);

/// Where the window opens, from the middle of the editor UI, and how big it is
const AT = Vec2(f32){ .x = 250, .y = 0 };
const SIZE = Vec2(f32){ .x = 400, .y = 460 };

mWindow: Entity = .uninit,
/// The window's content, which the list is built in
mContent: Entity = .uninit,
/// Why there is nothing to list, empty (and folded away) when there is
mMessage: Entity = .uninit,
mList: Components = .{},
/// The element the list was built for, null while none is built
mBuiltFor: ?UIElement = null,
/// Which components it had then
mBuiltPresent: Components.Present = .empty,
mOptions: Widgets.Options = .{},

/// Builds the window, closed and empty, at the top of `scene`
pub fn Build(engine_context: *EngineContext, scene: Scene, options: Widgets.Options) !UIElementPanel {
    const zone = Tracy.ZoneInit("UIElementPanel::Build", @src());
    defer zone.Deinit();
    const window = try Widgets.FloatingWindow(engine_context, scene, "UI Element", SIZE, AT, options);
    const self = UIElementPanel{
        .mWindow = window.Window,
        .mContent = window.Content,
        .mMessage = try Widgets.Label(engine_context, .{ .Entity = window.Content }, ""),
        .mOptions = options,
    };
    try WidgetActions.CloseWindow(engine_context, self.mWindow);
    return self;
}

pub fn Deinit(self: *UIElementPanel, engine_allocator: std.mem.Allocator) void {
    self.mList.Deinit(engine_allocator);
}

pub fn IsOpen(self: UIElementPanel) bool {
    return WidgetActions.IsWindowOpen(self.mWindow);
}

/// Opens the window in front of the others
pub fn Open(self: UIElementPanel, engine_context: *EngineContext) !void {
    try WidgetActions.OpenWindow(engine_context, self.mWindow);
}

/// Opens the window in front of the others, or closes it
pub fn Toggle(self: UIElementPanel, engine_context: *EngineContext) !void {
    if (self.IsOpen()) {
        try WidgetActions.CloseWindow(engine_context, self.mWindow);
    } else {
        try self.Open(engine_context);
    }
}

/// Once a frame, before layout, while it is open: the list built again if the selection or its components changed,
/// or a field asked for it, and the line saying why there is nothing to list
pub fn Update(self: *UIElementPanel, engine_context: *EngineContext, selected: ?SelectedObject) !void {
    const zone = Tracy.ZoneInit("UIElementPanel::Update", @src());
    defer zone.Deinit();
    if (!self.IsOpen()) return;

    const target = TargetOf(selected);
    if (target.Element) |element| {
        const present = Components.PresentOf(element);
        const stale = self.mBuiltFor == null or self.mBuiltFor.?.mID != element.mID or !present.eql(self.mBuiltPresent) or
            engine_context.mUIManager.TakeRebuild(self.mList.mRoot.?);
        if (stale) {
            try self.mList.Build(engine_context, self.mContent, self.mWindow, element, self.mOptions, null);
            self.mBuiltFor = element;
            self.mBuiltPresent = present;
            try self.mContent.MarkLayoutDirty(engine_context);
        }
    } else if (self.mBuiltFor != null) {
        try self.mList.Clear(engine_context);
        self.mBuiltFor = null;
    }
    try self.ShowMessage(engine_context, target.Message);
}

/// What clicking `item` does, null if it isn't one of the panel's menu items
pub fn ActionOf(self: *const UIElementPanel, item: Entity) ?Components.Action {
    return self.mList.ActionOf(item);
}

/// Does what a menu item asked for. The list is built again the next frame, seeing the components have changed
pub fn Run(self: *const UIElementPanel, engine_context: *EngineContext, action: Components.Action) !void {
    try self.mList.Run(engine_context, action);
}

/// The element to list, or why there is none
const Target = struct {
    Element: ?UIElement = null,
    Message: []const u8 = "",
};

fn TargetOf(selected: ?SelectedObject) Target {
    const object = selected orelse return .{ .Message = "Select an entity to see its UI element" };
    const entity = switch (object) {
        .entity => |entity| entity,
        else => return .{ .Message = "Only an entity can have a UI element" },
    };
    if (!entity.IsActive()) return .{};
    const element = UIManager.ElementOf(entity) orelse return .{ .Message = "This entity has no UI element. Add a UIElementComponent to it in the Components panel" };
    if (Components.PresentOf(element).count() == 0) return .{ .Element = element, .Message = "No UI components yet. Right click to add one" };
    return .{ .Element = element };
}

/// Puts `message` on the line, folded away while it says nothing
fn ShowMessage(self: UIElementPanel, engine_context: *EngineContext, message: []const u8) !void {
    try WidgetActions.SetText(engine_context, self.mMessage, message);
    const item = self.mMessage.GetComponent(LayoutItemComponent).?;
    const hidden = message.len == 0;
    if (item.mCollapsed == hidden) return;
    item.mCollapsed = hidden;
    try self.mMessage.MarkLayoutDirty(engine_context);
}
