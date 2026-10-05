//! The Audio Buses panel, in the editor's own UI: a floating window with the AudioManager's bus tree from Master down.
//! Each bus is a tree node titled with its name, and under it its name (not Master's), volume and pause, each from its
//! component's UIRender and kept in step by the bindings, then a row with Add Child and Delete (no Delete on Master),
//! then the buses under it. Every frame it is open the bus tree is checked against the one it was built from, and built
//! again when buses were added or deleted, or all replaced by opening a project. The buttons' clicks come in through
//! the editor's pointer events (ActionOf)
const std = @import("std");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const Bus = @import("../ECSObjects/Bus.zig");
const Widgets = @import("../UI/Widgets.zig");
const WidgetActions = @import("../UI/WidgetActions.zig");
const UIManager = @import("../UI/UIManager.zig");
const Inspector = @import("../UI/Inspector.zig");
const VComponents = @import("../ECSComponents/VComponents.zig");
const BusComponent = VComponents.BusComponent;
const VolumeComponent = VComponents.VolumeComponent;
const NameComponent = VComponents.NameComponent;
const LayoutItemComponent = @import("../ECSComponents/EComponents.zig").LayoutItemComponent;
const MathTypes = @import("../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;

const AudioBusesPanel = @This();

/// Where the window opens, from the middle of the editor UI, and how big it is
const AT = Vec2(f32){ .x = 150, .y = 100 };
const SIZE = Vec2(f32){ .x = 380, .y = 400 };

/// What a button of the panel does
pub const Action = union(enum) {
    /// a new bus under this one
    AddChild: Bus,
    /// this bus and every bus under it, at the end of the frame
    Delete: Bus,
};

const ButtonAction = struct {
    Button: Entity,
    Action: Action,
};

mWindow: Entity = .uninit,
/// The window's content, which the tree is built in
mContent: Entity = .uninit,
/// The tree as last built, null until the window is first open
mTree: ?Entity = null,
/// The buses the tree was built from, in the order it was built (each before the buses under it)
mBuilt: std.ArrayList(Bus.Type) = .empty,
/// Each bus's node title, in the same order
mTitles: std.ArrayList(Entity) = .empty,
/// What each of the tree's buttons does
mButtons: std.ArrayList(ButtonAction) = .empty,
mOptions: Widgets.Options = .{},

/// Builds the window, closed and empty, at the top of `scene`. The tree is built the first time it is open
pub fn Build(engine_context: *EngineContext, scene: Scene, options: Widgets.Options) !AudioBusesPanel {
    const zone = Tracy.ZoneInit("AudioBusesPanel::Build", @src());
    defer zone.Deinit();
    const window = try Widgets.FloatingWindow(engine_context, scene, "Audio Buses", SIZE, AT, options);
    const self = AudioBusesPanel{ .mWindow = window.Window, .mContent = window.Content, .mOptions = options };
    try WidgetActions.CloseWindow(engine_context, self.mWindow);
    return self;
}

pub fn Deinit(self: *AudioBusesPanel, engine_allocator: std.mem.Allocator) void {
    self.mBuilt.deinit(engine_allocator);
    self.mTitles.deinit(engine_allocator);
    self.mButtons.deinit(engine_allocator);
}

pub fn IsOpen(self: AudioBusesPanel) bool {
    return WidgetActions.IsWindowOpen(self.mWindow);
}

/// Opens the window in front of the others, or closes it
pub fn Toggle(self: AudioBusesPanel, engine_context: *EngineContext) !void {
    if (self.IsOpen()) {
        try WidgetActions.CloseWindow(engine_context, self.mWindow);
    } else {
        try WidgetActions.OpenWindow(engine_context, self.mWindow);
    }
}

/// Once a frame, before layout, while it is open: the tree built again if the buses have changed, and each bus's node
/// titled with its name
pub fn Update(self: *AudioBusesPanel, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("AudioBusesPanel::Update", @src());
    defer zone.Deinit();
    if (!self.IsOpen()) return;

    var buses: std.ArrayList(Bus) = .empty;
    try Walk(engine_context.FrameAllocator(), engine_context.mAudioManager.GetMasterBus(), &buses);
    if (!self.IsBuiltFrom(buses.items)) try self.Rebuild(engine_context);

    for (buses.items, self.mTitles.items) |bus, title| try WidgetActions.SetText(engine_context, title, NameOf(bus));
}

/// What clicking `button` does, null if it isn't one of the panel's buttons
pub fn ActionOf(self: *const AudioBusesPanel, button: Entity) ?Action {
    for (self.mButtons.items) |entry| {
        if (entry.Button.mID == button.mID and entry.Button.mManager == button.mManager) return entry.Action;
    }
    return null;
}

/// Does what a button asked for. The tree is built again the next frame, seeing the buses have changed
pub fn Run(engine_context: *EngineContext, action: Action) !void {
    switch (action) {
        .AddChild => |parent| _ = try parent.CreateChild(engine_context, .Entity, Bus.DefaultConfig),
        .Delete => |bus| try bus.Delete(engine_context),
    }
}

/// `bus` and every bus under it, each before the buses under it
fn Walk(frame_allocator: std.mem.Allocator, bus: Bus, buses: *std.ArrayList(Bus)) !void {
    try buses.append(frame_allocator, bus);
    var children = bus.GetIterator(.Child);
    while (children.next()) |child| try Walk(frame_allocator, child, buses);
}

fn IsBuiltFrom(self: AudioBusesPanel, buses: []const Bus) bool {
    if (self.mTree == null or buses.len != self.mBuilt.items.len) return false;
    for (buses, self.mBuilt.items) |bus, built| {
        if (bus.mID != built) return false;
    }
    return true;
}

/// The old tree hidden and deleted, and a new one built from the buses as they are now
fn Rebuild(self: *AudioBusesPanel, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("AudioBusesPanel::Rebuild", @src());
    defer zone.Deinit();
    if (self.mTree) |old| {
        //deleting only happens at the end of the frame, so it is hidden until then
        old.GetComponent(LayoutItemComponent).?.mCollapsed = true;
        try old.Delete(engine_context);
    }
    self.mBuilt.clearRetainingCapacity();
    self.mTitles.clearRetainingCapacity();
    self.mButtons.clearRetainingCapacity();

    const tree = try Widgets.Tree(engine_context, .{ .Entity = self.mContent });
    self.mTree = tree;
    const master = engine_context.mAudioManager.GetMasterBus();
    try self.BuildBus(engine_context, master, tree, master);
    try self.mContent.MarkLayoutDirty(engine_context);
}

fn BuildBus(self: *AudioBusesPanel, engine_context: *EngineContext, bus: Bus, parent: Entity, master: Bus) !void {
    const engine_allocator = engine_context.EngineAllocator();
    const node = try Widgets.TreeNode(engine_context, .{ .Entity = parent }, NameOf(bus), .{ .Open = true, .StockScripts = self.mOptions.StockScripts });
    try self.mBuilt.append(engine_allocator, bus.mID);
    try self.mTitles.append(engine_allocator, UIManager.LabelOf(node.Header).?);

    const content = node.Content.?;
    const is_master = bus.mID == master.mID;
    if (!is_master) try self.Rows(engine_context, bus, content, NameComponent);
    try self.Rows(engine_context, bus, content, VolumeComponent);
    try self.Rows(engine_context, bus, content, BusComponent);

    const buttons = try Widgets.Row(engine_context, .{ .Entity = content });
    try self.mButtons.append(engine_allocator, .{ .Button = try Widgets.Button(engine_context, .{ .Entity = buttons }, "Add Child"), .Action = .{ .AddChild = bus } });
    if (!is_master) {
        try self.mButtons.append(engine_allocator, .{ .Button = try Widgets.Button(engine_context, .{ .Entity = buttons }, "Delete"), .Action = .{ .Delete = bus } });
    }

    var children = bus.GetIterator(.Child);
    while (children.next()) |child| try self.BuildBus(engine_context, child, content, master);
}

/// The rows of one of the bus's components. A bus read from a hand edited file may be missing any of them
fn Rows(self: AudioBusesPanel, engine_context: *EngineContext, bus: Bus, content: Entity, comptime component_type: type) !void {
    const component = bus.GetComponent(component_type) orelse return;
    var builder = Inspector.ForComponent(engine_context, content, content, bus, component_type, self.mOptions);
    try component.UIRender(&builder);
}

fn NameOf(bus: Bus) []const u8 {
    return if (bus.GetComponent(NameComponent)) |name| name.mName.items else "Bus";
}
