//! The Collision Layer Names panel, in the editor's own UI: a floating window with a row per collision layer, its
//! number and a text field with its name (CollisionLayers), opened from the Project menu. A name is kept when Enter is
//! pressed or the field is left (its TextSubmitted, OnUIEvent). An emptied name goes back to the layer's number. The
//! fields are given the names again whenever they change, a project opened or a name cut short
const std = @import("std");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const Widgets = @import("../UI/Widgets.zig");
const WidgetActions = @import("../UI/WidgetActions.zig");
const UIManager = @import("../UI/UIManager.zig");
const CollisionLayers = @import("../Physics/CollisionLayers.zig");
const EntityUIEvent = @import("../Events/UIEventData.zig").EntityEvent;
const EntityComponents = @import("../ECSComponents/EComponents.zig");
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const TextComponent = EntityComponents.TextComponent;
const MathTypes = @import("../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;

const CollisionLayersPanel = @This();

/// Where the window opens, from the middle of the editor UI, and how big it is
const AT = Vec2(f32){ .x = -150, .y = 100 };
const SIZE = Vec2(f32){ .x = 340, .y = 460 };
/// How wide a row's layer number is
const NUMBER_WIDTH: f32 = 70;

mWindow: Entity = .uninit,
/// Each layer's text field's text, which TextSubmitted is sent from, in bit order
mFields: [CollisionLayers.COUNT]Entity = @splat(.uninit),
/// The names the fields were last given (CollisionLayers.mVersion)
mShownVersion: ?u32 = null,

/// Builds the window, closed, at the top of `scene`
pub fn Build(engine_context: *EngineContext, scene: Scene, options: Widgets.Options) !CollisionLayersPanel {
    const zone = Tracy.ZoneInit("CollisionLayersPanel::Build", @src());
    defer zone.Deinit();
    const window = try Widgets.FloatingWindow(engine_context, scene, "Collision Layer Names", SIZE, AT, options);
    var self = CollisionLayersPanel{ .mWindow = window.Window };

    const layers = &engine_context.mCollisionLayers;
    for (&self.mFields, 0..) |*field, layer| {
        const row = try Widgets.Row(engine_context, .{ .Entity = window.Content });
        row.GetComponentMut(LayoutItemComponent).?.mWidth = .{ .Fill = 1 };
        var number: [16]u8 = undefined;
        const shown_number = try Widgets.Label(engine_context, .{ .Entity = row }, try std.fmt.bufPrint(&number, "Layer {d}", .{layer + 1}));
        shown_number.GetComponentMut(LayoutItemComponent).?.mWidth = .{ .Fixed = NUMBER_WIDTH };
        const text_field = try Widgets.TextField(engine_context, .{ .Entity = row }, layers.GetName(layer));
        field.* = UIManager.LabelOf(text_field).?;
    }
    self.mShownVersion = layers.mVersion;

    try WidgetActions.CloseWindow(engine_context, self.mWindow);
    return self;
}

pub fn IsOpen(self: CollisionLayersPanel) bool {
    return WidgetActions.IsWindowOpen(self.mWindow);
}

/// Opens the window in front of the others, or closes it
pub fn Toggle(self: CollisionLayersPanel, engine_context: *EngineContext) !void {
    if (self.IsOpen()) {
        try WidgetActions.CloseWindow(engine_context, self.mWindow);
    } else {
        try WidgetActions.OpenWindow(engine_context, self.mWindow);
    }
}

/// Once a frame, before layout, while it is open: the fields given the names again if they have changed
pub fn Update(self: *CollisionLayersPanel, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("CollisionLayersPanel::Update", @src());
    defer zone.Deinit();
    if (!self.IsOpen()) return;
    const layers = &engine_context.mCollisionLayers;
    if (self.mShownVersion == layers.mVersion) return;
    for (self.mFields, 0..) |field, layer| try WidgetActions.SetText(engine_context, field, layers.GetName(layer));
    self.mShownVersion = layers.mVersion;
}

/// One of the frame's UI events: a field's name kept renames its layer
pub fn OnUIEvent(self: *CollisionLayersPanel, engine_context: *EngineContext, event: EntityUIEvent) !void {
    const submitted = switch (event.mEvent) {
        .TextSubmitted => |e| e.mTarget,
        else => return,
    };
    //one event per entity in the chain: the field's own
    if (event.mEntity.mID != submitted.mID or event.mEntity.mManager != submitted.mManager) return;
    for (self.mFields, 0..) |field, layer| {
        if (field.mID != submitted.mID or field.mManager != submitted.mManager) continue;
        const text = field.GetComponent(TextComponent) orelse return;
        engine_context.mCollisionLayers.SetName(layer, text.mText.items);
        //what was typed may not be what was kept (emptied, cut short), so the field is shown the name again
        self.mShownVersion = null;
        return;
    }
}
