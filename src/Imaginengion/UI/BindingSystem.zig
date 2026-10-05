//! Widgets tied to fields (FieldBindingComponent, made by Inspector.Builder): every frame each one shows its field's
//! value, unless it is being typed into or dragged, and an edit (its ValueChanged, or TextSubmitted for a text field)
//! is written into the field. After a write the field's own OnChange runs, then what its component needs after an edit
//! (dirty tags), and an inspector whose field decides what else is shown is asked to be built again (TakeRebuild).
//! Showing a value never sends an event, so a widget never hears back what it was just given. Part of the UIManager.
const std = @import("std");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const UIElement = @import("../ECSObjects/UIElement.zig");
const UIEvent = @import("../Events/UIEventData.zig").EventT;
const UIManager = @import("UIManager.zig");
const WidgetActions = @import("WidgetActions.zig");
const Inspector = @import("Inspector.zig");

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const AttribComponent = EntityComponents.AttribComponent;
const TextComponent = EntityComponents.TextComponent;
const SelectedTag = EntityComponents.SelectedTag;
const FieldBindingComponent = @import("../ECSComponents/UIComponents.zig").FieldBindingComponent;

const BindingSystem = @This();

pub const empty: BindingSystem = .{};

/// The inspectors asked to be built again, by a field that decides what else they show
mRebuild: std.ArrayList(Entity) = .empty,

pub fn Deinit(self: *BindingSystem, engine_allocator: std.mem.Allocator) void {
    self.mRebuild.deinit(engine_allocator);
}

/// Whether the inspector `root` was asked to be built again, which it no longer is once this has said so
pub fn TakeRebuild(self: *BindingSystem, root: Entity) bool {
    for (self.mRebuild.items, 0..) |asked, i| {
        if (asked.mID == root.mID and asked.mManager == root.mManager) {
            _ = self.mRebuild.swapRemove(i);
            return true;
        }
    }
    return false;
}

/// Once a frame, before the number fields show their values: every bound widget not being edited shows its field
pub fn Update(_: *BindingSystem, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("BindingSystem::Update", @src());
    defer zone.Deinit();
    const ui_manager = &engine_context.mUIManager;
    const element_ids = try ui_manager.GetGroup(engine_context.FrameAllocator(), .{ .Component = FieldBindingComponent });
    for (element_ids.items) |element_id| {
        const element = UIElement{ .mID = element_id, .mManager = ui_manager };
        const widget = element.GetOwner();
        if (!widget.IsIDValid() or !widget.IsActive()) continue;
        const binding = element.GetComponent(FieldBindingComponent).?.*;
        if (IsBeingEdited(engine_context, widget)) continue;
        const field = FieldOf(binding) orelse continue;
        try Show(engine_context, widget, Shown(binding, binding.mAccess.Read(field)));
    }
}

/// One of the frame's UI events: a bound widget's edit is written into its field
pub fn OnUIEvent(self: *BindingSystem, engine_context: *EngineContext, event: UIEvent) !void {
    const zone = Tracy.ZoneInit("BindingSystem::OnUIEvent", @src());
    defer zone.Deinit();
    //one event per entity in the chain: the bound widget's own
    const widget = switch (event) {
        .ValueChanged => |e| e.mEntity,
        .TextSubmitted => |e| if (e.mEntity.mID == e.mTarget.mID) e.mEntity else return,
        else => return,
    };
    const binding = (UIManager.GetUIComponent(widget, FieldBindingComponent) orelse return).*;
    const value = ValueOf(binding, widget) orelse return;
    const component = binding.mResolve(binding.mObject) orelse return;
    const field: *anyopaque = @ptrFromInt(@intFromPtr(component) + binding.mOffset);
    try binding.mAccess.Write(engine_context, field, value);

    if (binding.mOnChange) |on_change| on_change(component);
    try binding.mAfterEdit(engine_context, binding.mObject);
    if (binding.mRebuild) |root| {
        for (self.mRebuild.items) |asked| {
            if (asked.mID == root.mID and asked.mManager == root.mManager) return;
        }
        try self.mRebuild.append(engine_context.EngineAllocator(), root);
    }
}

/// Where a binding's field is right now, null once its object or component has gone
fn FieldOf(binding: FieldBindingComponent) ?*anyopaque {
    const component = binding.mResolve(binding.mObject) orelse return null;
    return @ptrFromInt(@intFromPtr(component) + binding.mOffset);
}

/// A field's value as its widget shows it: a converted number in its shown form
fn Shown(binding: FieldBindingComponent, value: Inspector.Value) Inspector.Value {
    const convert = binding.mConvert orelse return value;
    return switch (value) {
        .Number => |number| .{ .Number = convert.ToShown(number) },
        else => value,
    };
}

/// The value a widget holds, as its field keeps it: a converted number back in its kept form
fn ValueOf(binding: FieldBindingComponent, widget: Entity) ?Inspector.Value {
    const shown: Inspector.Value = switch (binding.mAccess.Read(FieldOf(binding) orelse return null)) {
        .Number => .{ .Number = (widget.GetComponent(AttribComponent) orelse return null).mData.AsFloat() },
        .Bool => .{ .Bool = widget.HasComponent(SelectedTag) },
        .Choice => .{ .Choice = WidgetActions.ChosenIndex(widget) orelse return null },
        .Color => .{ .Color = WidgetActions.ColorOf(widget) },
        .Text => .{ .Text = (widget.GetComponent(TextComponent) orelse return null).mText.items },
    };
    const convert = binding.mConvert orelse return shown;
    return switch (shown) {
        .Number => |number| .{ .Number = convert.FromShown(number) },
        else => shown,
    };
}

/// Puts a value on a widget without sending anything
fn Show(engine_context: *EngineContext, widget: Entity, value: Inspector.Value) !void {
    switch (value) {
        .Number => |number| {
            const attrib = widget.GetComponent(AttribComponent) orelse return;
            if (attrib.mData.AsFloat() != number) attrib.mData.SetFromFloat(number);
        },
        .Bool => |checked| {
            if (checked == widget.HasComponent(SelectedTag)) return;
            if (checked) {
                _ = try widget.AddComponent(engine_context, SelectedTag{});
            } else {
                try widget.RemoveComponentSync(engine_context, SelectedTag);
            }
        },
        .Choice => |index| try WidgetActions.ShowChosen(engine_context, widget, index),
        .Color => |color| WidgetActions.ShowColor(widget, color),
        .Text => |text| {
            const text_component = widget.GetComponent(TextComponent) orelse return;
            if (std.mem.eql(u8, text_component.mText.items, text)) return;
            try text_component.SetText(engine_context, text);
            try widget.MarkLayoutDirty(engine_context);
        },
    }
}

/// Whether a widget, or anything in it, is being typed into or dragged: then it is the player's, not the field's
fn IsBeingEdited(engine_context: *EngineContext, widget: Entity) bool {
    const ui_manager = &engine_context.mUIManager;
    if (ui_manager.mFocusSystem.Focused()) |focused| {
        if (IsInside(focused, widget)) return true;
    }
    if (ui_manager.mNumberFieldSystem.mDragged) |dragged| {
        if (dragged.IsActive() and IsInside(dragged, widget)) return true;
    }
    return false;
}

/// Whether `entity` is `container` or inside it
fn IsInside(entity: Entity, container: Entity) bool {
    var current = entity;
    while (true) {
        if (current.mID == container.mID and current.mManager == container.mManager) return true;
        const child_component = current.GetComponent(@import("../ECS/Components.zig").ChildComponent(Entity.Type)) orelse return false;
        current = Entity{ .mID = child_component.mParent, .mManager = current.mManager };
    }
}
