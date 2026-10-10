//! Widgets tied to fields (FieldBindingComponent, made by Inspector.Builder): every frame each one shows its field's
//! value, unless it is being typed into or dragged, and an edit (its ValueChanged, or TextSubmitted for a text field)
//! is written into the field. An asset field is written by a file dropped on it instead (OnPointerEvent). After a write
//! the field's own OnChange runs, then what its component needs after an edit (dirty tags), and an inspector whose
//! field decides what else is shown is asked to be built again (TakeRebuild).
//! Showing a value never sends an event, so a widget never hears back what it was just given. Part of the UIManager.
const std = @import("std");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const UIElement = @import("../ECSObjects/UIElement.zig");
const EntityUIEvent = @import("../Events/UIEventData.zig").EntityEvent;
const EntityPointerEvent = @import("../Events/PointerEventData.zig").EntityEvent;
const AssetHandle = @import("../ECSObjects/AssetHandle.zig");
const MathTypes = @import("../Math/MathTypes.zig");
const Quat = MathTypes.Quat;
const Vec3 = MathTypes.Vec3;
const UIManager = @import("UIManager.zig");
const WidgetActions = @import("WidgetActions.zig");
const Inspector = @import("Inspector.zig");

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const AttribComponent = EntityComponents.AttribComponent;
const TextComponent = EntityComponents.TextComponent;
const SelectedTag = EntityComponents.SelectedTag;
const SurfaceComponent = EntityComponents.SurfaceComponent;
const FileRefComponent = EntityComponents.FileRefComponent;
const ObjectRefComponent = EntityComponents.ObjectRefComponent;
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
        //a Clear menu item only writes
        if (binding.mClear != null) continue;
        if (IsBeingEdited(engine_context, widget)) continue;
        const field = FieldOf(binding) orelse continue;
        try Show(engine_context, widget, Shown(binding, binding.mAccess.Read(field)));
    }
}

/// One of the frame's UI events: a bound widget's edit is written into its field
pub fn OnUIEvent(self: *BindingSystem, engine_context: *EngineContext, event: EntityUIEvent) !void {
    const zone = Tracy.ZoneInit("BindingSystem::OnUIEvent", @src());
    defer zone.Deinit();
    //one event per entity in the chain: the bound widget's own
    const widget = switch (event.mEvent) {
        .ValueChanged => event.mEntity,
        .TextSubmitted => |e| if (event.mEntity.mID == e.mTarget.mID) event.mEntity else return,
        else => return,
    };
    const binding = (UIManager.GetUIComponent(widget, FieldBindingComponent) orelse return).*;
    const value = ValueOf(binding, widget) orelse return;
    try self.Write(engine_context, binding, value);
}

/// One of the frame's pointer events: a file dropped on an asset field that takes its kind becomes the field's asset, a
/// hierarchy row dropped on a reference field that takes its kind becomes the field's object, and a field's Clear
/// clicked writes what it clears to
pub fn OnPointerEvent(self: *BindingSystem, engine_context: *EngineContext, event: EntityPointerEvent) !void {
    const dropped = switch (event.mEvent) {
        .PointerDropped => |e| e,
        .PointerClicked => |e| {
            if (e.mButton != .BUTTON_LEFT) return;
            const binding = (UIManager.GetUIComponent(event.mEntity, FieldBindingComponent) orelse return).*;
            const cleared = binding.mClear orelse return;
            return try self.Write(engine_context, binding, cleared);
        },
        else => return,
    };
    const zone = Tracy.ZoneInit("BindingSystem::OnPointerEvent", @src());
    defer zone.Deinit();
    const binding = (UIManager.GetUIComponent(event.mEntity, FieldBindingComponent) orelse return).*;
    if (binding.mTakes) |kind| {
        const object_ref = dropped.mSource.GetComponent(ObjectRefComponent) orelse return;
        if (std.meta.activeTag(object_ref.mObject) != kind) {
            const kind_name = switch (kind) {
                .entity => "an entity",
                .scene_layer => "a scene",
                .player => "a player",
                .gamecontext => "a game mode",
            };
            std.log.warn("Only {s} can go in this field", .{kind_name});
            return;
        }
        return try self.Write(engine_context, binding, .{ .Ref = object_ref.mObject });
    }
    if (binding.mAccepts.len == 0) return;
    const file_ref = dropped.mSource.GetComponent(FileRefComponent) orelse return;
    const extension = std.fs.path.extension(file_ref.mRelPath.items);
    for (binding.mAccepts) |accepted| {
        if (std.ascii.eqlIgnoreCase(extension, accepted)) break;
    } else {
        std.log.warn("{s} can't go in this field, it takes {s} files", .{ file_ref.mRelPath.items, binding.mAccepts[0] });
        return;
    }
    const asset = try engine_context.mAssetManager.GetAssetHandle(engine_context, .{ .File = .{ .rel_path = file_ref.mRelPath.items, .path_type = file_ref.mPathType } });
    try self.Write(engine_context, binding, .{ .Asset = asset });
}

/// Writes a value into a binding's field, then what has to happen after an edit
fn Write(self: *BindingSystem, engine_context: *EngineContext, binding: FieldBindingComponent, value: Inspector.Value) !void {
    const component = binding.mResolve(binding.mObject) orelse return;
    const field: *anyopaque = @ptrFromInt(@intFromPtr(component) + binding.mOffset);
    try binding.mAccess.Write(engine_context, field, value);

    if (binding.mOnChange) |on_change| on_change(component);
    const reshaped = try binding.mAfterEdit(engine_context, binding.mObject);
    if (binding.mRebuilds or reshaped) {
        const root = binding.mRoot;
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
        .Rotation => .{ .Rotation = Quat(f32).FromDegrees(DegreesOf(widget)) },
        //only ever written by a drop
        .Asset, .Ref => return null,
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
        .Text => |text| try ShowText(engine_context, widget, text),
        .Rotation => |rotation| {
            //the numbers being edited stay as they are while they still make this rotation: only a rotation changed by
            //something else sets them again
            if (SameRotation(Quat(f32).FromDegrees(DegreesOf(widget)), rotation)) return;
            const degrees = rotation.ToDegrees();
            var numbers = widget.GetIterator(.Child);
            var axis: usize = 0;
            while (numbers.next()) |number| {
                const attrib = number.GetComponent(AttribComponent) orelse continue;
                const angle: f32 = switch (axis) {
                    0 => degrees.x,
                    1 => degrees.y,
                    else => degrees.z,
                };
                attrib.mData.SetFromFloat(angle);
                axis += 1;
            }
        },
        .Asset => |asset| {
            //a name on a label, or the asset itself on a thumbnail
            if (UIManager.LabelOf(widget)) |label| return try ShowText(engine_context, label, AssetName(asset));
            const surface = widget.GetComponent(SurfaceComponent) orelse return;
            if (surface.mTexture.mID == asset.mID) return;
            surface.mTexture.ReleaseAsset();
            surface.mTexture = asset;
            asset.RetainAsset();
        },
        //never read from a field
        .Ref => {},
    }
}

/// Text on a label, or on the label inside a box (a reference field's)
fn ShowText(engine_context: *EngineContext, widget: Entity, text: []const u8) !void {
    const label = if (widget.HasComponent(TextComponent)) widget else UIManager.LabelOf(widget) orelse return;
    const text_component = label.GetComponent(TextComponent).?;
    if (std.mem.eql(u8, text_component.mText.items, text)) return;
    try text_component.SetText(engine_context, text);
    try label.MarkLayoutDirty(engine_context);
}

/// What an asset field shows: the asset's file name without its extension, "None" for none
fn AssetName(asset: AssetHandle) []const u8 {
    if (asset.mID == AssetHandle.NullObject) return "None";
    return std.fs.path.stem(std.fs.path.basename(asset.GetFileMetaData().mRelPath.items));
}

/// A rotation row's X, Y and Z, its numbers in order
fn DegreesOf(row: Entity) Vec3(f32) {
    var degrees = [3]f32{ 0, 0, 0 };
    var numbers = row.GetIterator(.Child);
    var axis: usize = 0;
    while (numbers.next()) |number| {
        const attrib = number.GetComponent(AttribComponent) orelse continue;
        if (axis < 3) degrees[axis] = @floatCast(attrib.mData.AsFloat());
        axis += 1;
    }
    return .{ .x = degrees[0], .y = degrees[1], .z = degrees[2] };
}

/// Whether two rotations turn things the same way, near enough: q and -q are the same rotation
fn SameRotation(a: Quat(f32), b: Quat(f32)) bool {
    const dot = a.w * b.w + a.x * b.x + a.y * b.y + a.z * b.z;
    return @abs(dot) > 1 - 1e-5;
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
