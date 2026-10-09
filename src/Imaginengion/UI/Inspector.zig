//! Building the UI that edits an object's component, out of the editor UI's widgets: the retained version of what
//! EditorRender does in ImGui. A component (or any struct in it) that has a
//!     pub fn UIRender(self: *T, ui: *Inspector.Builder) !void
//! is shown by calling it once, when the inspector is built. Each Builder call makes a widget for one field and ties
//! the widget to it (FieldBindingComponent): from then on the binding system (UI/BindingSystem.zig) keeps the widget
//! showing the field and writes edits back into it. A struct without a UIRender shows nothing.
//! A widget can't keep a pointer to its field: components move in memory as their ECS grows. So it keeps where the field
//! is inside its component (its offset), and the component is looked up again each time it is needed.
const std = @import("std");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const Player = @import("../ECSObjects/Player.zig");
const GameContext = @import("../ECSObjects/GameContext.zig");
const Bus = @import("../ECSObjects/Bus.zig");
const UIElement = @import("../ECSObjects/UIElement.zig");
const AssetHandle = @import("../ECSObjects/AssetHandle.zig");
const WidgetActions = @import("WidgetActions.zig");
const UIManager = @import("UIManager.zig");
const Widgets = @import("Widgets.zig");
const LayoutSystem = @import("LayoutSystem.zig");
const MathTypes = @import("../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;
const Vec4 = MathTypes.Vec4;
const Quat = MathTypes.Quat;

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const LayoutComponent = EntityComponents.LayoutComponent;
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const TextComponent = EntityComponents.TextComponent;
const TransformComponent = EntityComponents.TransformComponent;
const RigidBodyComponent = EntityComponents.RigidBodyComponent;
const UIElementComponent = EntityComponents.UIElementComponent;
const NameComponent = EntityComponents.NameComponent;
const UIComponents = @import("../ECSComponents/UIComponents.zig");
const FieldBindingComponent = UIComponents.FieldBindingComponent;
const NumberFieldComponent = UIComponents.NumberFieldComponent;
const ScrollComponent = UIComponents.ScrollComponent;
const PopupComponent = UIComponents.PopupComponent;

/// How wide a field's label is, in canvas units: every field of an inspector lines up after it
pub const LABEL_WIDTH: f32 = 120;

/// The object a component being edited is on: any of the four object types, an audio bus (in the AudioManager's ECS),
/// or an entity's UI element (in the UIManager's)
pub const ObjectRef = union(enum) {
    Entity: Entity,
    Scene: Scene,
    Player: Player,
    GameContext: GameContext,
    Bus: Bus,
    UIElement: UIElement,

    fn Of(object: anytype) ObjectRef {
        return switch (@TypeOf(object)) {
            Entity => .{ .Entity = object },
            Scene => .{ .Scene = object },
            Player => .{ .Player = object },
            GameContext => .{ .GameContext = object },
            Bus => .{ .Bus = object },
            UIElement => .{ .UIElement = object },
            else => @compileError("Not an object type: " ++ @typeName(@TypeOf(object))),
        };
    }
};

/// A field's value as a widget shows it
pub const Value = union(enum) {
    Number: f64,
    Bool: bool,
    /// which of an enum's values, by its place among them
    Choice: usize,
    Color: Vec4(f32),
    Text: []const u8,
    /// a rotation, shown as X, Y and Z in degrees
    Rotation: Quat(f32),
    /// an asset field's asset: only ever written by a file dropped on its widget
    Asset: AssetHandle,
};

/// Reading and writing a field of one type, as a Value
pub const Access = struct {
    Read: *const fn (field: *anyopaque) Value,
    Write: *const fn (engine_context: *EngineContext, field: *anyopaque, value: Value) anyerror!void,
};

/// How a number is shown when it is kept as something else, e.g. an angle kept in radians and shown in degrees
pub const Conversion = struct {
    /// from what is kept to what is shown
    ToShown: *const fn (f64) f64,
    /// and back
    FromShown: *const fn (f64) f64,
};

/// Run after a field is edited, with the component it is in: e.g. working something out again from it
pub const OnChange = *const fn (component: *anyopaque) void;

/// For a number field
pub const NumberOptions = struct {
    /// how much it changes per unit dragged
    Speed: f32 = 0.1,
    Min: ?f32 = null,
    Max: ?f32 = null,
    Decimals: u8 = 3,
    Convert: ?Conversion = null,
    OnChange: ?OnChange = null,
};

/// For a union: its case's own rows go under the dropdown of cases
pub const UnionOptions = struct {
    OnChange: ?OnChange = null,
    /// for a case that is a number
    Number: NumberOptions = .{},
};

/// For an asset field
pub const AssetOptions = struct {
    /// a small picture of the asset beside its name, for a texture
    Thumbnail: bool = false,
    OnChange: ?OnChange = null,
    Rebuilds: bool = false,
};

pub const FieldOptions = struct {
    OnChange: ?OnChange = null,
    /// the inspector is built again when it is edited: a field that decides which of the others are shown
    Rebuilds: bool = false,
};

/// What UIRender is handed: makes a row for each field asked for, in order, under the component's section
pub const Builder = struct {
    mEngineContext: *EngineContext,
    /// where the rows go
    mParent: Entity,
    /// what is built again when a field that rebuilds is edited
    mRoot: Entity,
    mObject: ObjectRef,
    /// the component as it was when this was built, which field offsets are measured from
    mBase: usize,
    mResolve: *const fn (ObjectRef) ?*anyopaque,
    mAfterEdit: *const fn (*EngineContext, ObjectRef) anyerror!void,
    mOptions: Widgets.Options,

    pub fn Float(self: *Builder, field: *f32, label: []const u8, options: NumberOptions) !void {
        try self.Number(f32, field, label, options);
    }

    pub fn Int(self: *Builder, field: *i32, label: []const u8, options: NumberOptions) !void {
        try self.Number(i32, field, label, options);
    }

    pub fn UInt(self: *Builder, field: *u32, label: []const u8, options: NumberOptions) !void {
        try self.Number(u32, field, label, options);
    }

    pub fn UInt8(self: *Builder, field: *u8, label: []const u8, options: NumberOptions) !void {
        try self.Number(u8, field, label, options);
    }

    /// A number that can be left out, like a limit: a checkbox for whether there is one, and the number beside it,
    /// greyed out while there isn't. Ticking it starts the number at 0. Ticking or unticking builds the inspector again
    pub fn OptionalFloat(self: *Builder, field: *?f32, label: []const u8, options: NumberOptions) !void {
        const row = try self.Row(label);
        const checkbox = try Widgets.Checkbox(self.mEngineContext, .{ .Entity = row }, "", self.mOptions);
        //the box, which the toggle's ValueChanged is sent from
        var parts = checkbox.GetIterator(.Child);
        try self.Bind(parts.next().?, field, &OPTIONAL_SET, options.OnChange, null, true);

        const number_field = try Widgets.NumberField(self.mEngineContext, .{ .Entity = row }, .{ .float32 = field.* orelse 0 }, .{
            .mSpeed = options.Speed,
            .mMin = options.Min,
            .mMax = options.Max,
            .mDecimals = options.Decimals,
        });
        try self.Bind(number_field, field, &OPTIONAL_VALUE, options.OnChange, options.Convert, false);
        if (field.* == null) try WidgetActions.SetDisabled(self.mEngineContext, number_field, true);
    }

    /// A dropdown of `choices` for a field that isn't an enum, read and written by `access`, whose Read gives the
    /// .Choice shown: e.g. a preset that sets several values at once
    pub fn Choice(self: *Builder, field: anytype, label: []const u8, choices: []const []const u8, access: *const Access, options: FieldOptions) !void {
        const row = try self.Row(label);
        const chosen: ?usize = switch (access.Read(@ptrCast(field))) {
            .Choice => |index| index,
            else => null,
        };
        const dropdown = try Widgets.Dropdown(self.mEngineContext, .{ .Entity = row }, choices, chosen, self.mOptions);
        try self.Bind(dropdown, field, access, options.OnChange, null, options.Rebuilds);
    }

    /// A rotation, as X, Y and Z in degrees. The three numbers are what is being edited: they are only set again from
    /// the rotation when something else changed it, since a rotation can be the same for different angles, and turning
    /// it back into angles part way through a drag could jump them (Y past 90 flips X and Z)
    pub fn Rotation(self: *Builder, field: *Quat(f32), label: []const u8, options: NumberOptions) !void {
        //read before any widget is made, which can move the component when it is in the same ECS
        const degrees = field.ToDegrees();
        const row = try self.Row(label);
        const numbers = try Widgets.NumberRow(self.mEngineContext, .{ .Entity = row }, &.{ degrees.x, degrees.y, degrees.z }, .{
            .mSpeed = options.Speed,
            .mMin = options.Min,
            .mMax = options.Max,
            .mDecimals = options.Decimals,
        });
        //the whole row, which each number's ValueChanged reaches too
        try self.Bind(numbers, field, AccessFor(Quat(f32)), options.OnChange, null, false);
    }

    /// A tagged union: a dropdown of its cases, named as they are in the code, then the case's own rows. A case that is
    /// a number or a bool is one field named after the case, one that is a struct shows its UIRender's rows, and one with
    /// nothing in it shows nothing. Picking another case starts it at the union's DefaultFor(tag) if it has one, else at
    /// the case's own default, and builds the inspector again
    pub fn Union(self: *Builder, field: anytype, label: []const u8, options: UnionOptions) !void {
        const U = @typeInfo(@TypeOf(field)).pointer.child;
        const names = comptime @typeInfo(U).@"union".field_names;
        const chosen = CaseOf(U, field.*);
        const row = try self.Row(label);
        var choices: [names.len][]const u8 = undefined;
        inline for (names, 0..) |name, i| choices[i] = name;
        const dropdown = try Widgets.Dropdown(self.mEngineContext, .{ .Entity = row }, &choices, chosen, self.mOptions);
        try self.Bind(dropdown, field, UnionCaseAccess(U), options.OnChange, null, true);

        switch (field.*) {
            inline else => |*payload, tag| {
                const P = @TypeOf(payload.*);
                const case_name = @tagName(tag);
                switch (P) {
                    void => {},
                    f32 => try self.Float(payload, case_name, MergeOnChange(options.Number, options.OnChange)),
                    i32 => try self.Int(payload, case_name, MergeOnChange(options.Number, options.OnChange)),
                    u32 => try self.UInt(payload, case_name, MergeOnChange(options.Number, options.OnChange)),
                    u8 => try self.UInt8(payload, case_name, MergeOnChange(options.Number, options.OnChange)),
                    bool => try self.Bool(payload, case_name, .{ .OnChange = options.OnChange }),
                    else => try self.Fields(payload),
                }
            },
        }
    }

    /// A struct inside the component shown in place: its UIRender's rows go with the ones around them, under no header
    /// of their own (see Struct for one under a header). A struct without a UIRender shows nothing
    pub fn Fields(self: *Builder, field: anytype) !void {
        const T = @typeInfo(@TypeOf(field)).pointer.child;
        if (comptime @typeInfo(T) != .@"struct" or !@hasDecl(T, "UIRender")) return;
        try field.UIRender(self);
    }

    /// A field shown and never edited, as `show` writes it into the buffer it is handed (at most 64 bytes), e.g. an id
    /// or a size worked out by something else
    pub fn Readout(self: *Builder, field: anytype, label: []const u8, comptime show: anytype) !void {
        const T = @typeInfo(@TypeOf(field)).pointer.child;
        var buffer: [READOUT_LEN]u8 = undefined;
        const text = show(field.*, &buffer);
        const row = try self.Row(label);
        const shown = try Widgets.Label(self.mEngineContext, .{ .Entity = row }, text);
        try self.Bind(shown, field, ReadoutAccess(T, show), null, null, false);
    }

    /// A set of bits (a std.StaticBitSet): a numbered checkbox for each, as many to a row as fit
    pub fn Flags(self: *Builder, field: anytype, label: []const u8, options: FieldOptions) !void {
        const T = @typeInfo(@TypeOf(field)).pointer.child;
        const row = try self.Row(label);
        const grid = try Widgets.Grid(self.mEngineContext, .{ .Entity = row }, Widgets.PADDING / 2);
        inline for (0..T.bit_length) |bit| {
            var number: [4]u8 = undefined;
            const checkbox = try Widgets.Checkbox(self.mEngineContext, .{ .Entity = grid }, try std.fmt.bufPrint(&number, "{d}", .{bit}), self.mOptions);
            var parts = checkbox.GetIterator(.Child);
            try self.Bind(parts.next().?, field, BitAccess(T, bit), options.OnChange, null, options.Rebuilds);
        }
    }

    /// An asset field: the asset's file name, "None" for no asset, and a file dropped on it from the Content Browser
    /// whose extension is one of `accepts` (e.g. ".png") becomes its asset. With no extensions it only shows the asset.
    /// `accepts` has to outlive the inspector, so it is a literal
    pub fn Asset(self: *Builder, field: *AssetHandle, label: []const u8, comptime accepts: []const []const u8, options: AssetOptions) !void {
        const row = try self.Row(label);
        if (options.Thumbnail) {
            const thumbnail = try Widgets.Image(self.mEngineContext, .{ .Entity = row }, .uninit, .{ .x = THUMBNAIL_SIZE, .y = THUMBNAIL_SIZE });
            try self.Bind(thumbnail, field, AccessFor(AssetHandle), null, null, false);
        }
        const shown = if (accepts.len > 0) try Widgets.DropBox(self.mEngineContext, .{ .Entity = row }, "") else try Widgets.Label(self.mEngineContext, .{ .Entity = row }, "");
        try self.Bind(shown, field, AccessFor(AssetHandle), options.OnChange, null, options.Rebuilds);
        UIManager.GetUIComponent(shown, FieldBindingComponent).?.mAccepts = accepts;
    }

    /// Buttons side by side, one for each of `texts`, in their own row with no label. They do nothing when clicked:
    /// whoever built the inspector handles their clicks
    pub fn Buttons(self: *Builder, comptime texts: []const []const u8) ![texts.len]Entity {
        const row = try Widgets.Row(self.mEngineContext, .{ .Entity = self.mParent });
        var buttons: [texts.len]Entity = undefined;
        inline for (texts, 0..) |text, i| buttons[i] = try Widgets.Button(self.mEngineContext, .{ .Entity = row }, text);
        return buttons;
    }

    /// The name of the entity an entity field points at, "None" when it points at none. Shown only, not edited
    pub fn EntityName(self: *Builder, field: *Entity, label: []const u8) !void {
        try self.ObjectName(Entity, field, label);
    }

    /// The same for a scene field
    pub fn SceneName(self: *Builder, field: *Scene, label: []const u8) !void {
        try self.ObjectName(Scene, field, label);
    }

    fn ObjectName(self: *Builder, comptime T: type, field: *T, label: []const u8) !void {
        const shown_name = NameOf(field.*);
        const row = try self.Row(label);
        const shown = try Widgets.Label(self.mEngineContext, .{ .Entity = row }, shown_name);
        try self.Bind(shown, field, NameAccess(T), null, null, false);
    }

    pub fn Bool(self: *Builder, field: *bool, label: []const u8, options: FieldOptions) !void {
        const row = try self.Row(label);
        const checkbox = try Widgets.Checkbox(self.mEngineContext, .{ .Entity = row }, "", self.mOptions);
        //the box, which the toggle's ValueChanged is sent from
        var parts = checkbox.GetIterator(.Child);
        try self.Bind(parts.next().?, field, AccessFor(bool), options.OnChange, null, options.Rebuilds);
    }

    /// A dropdown of an enum's values, named as they are in the code
    pub fn Enum(self: *Builder, comptime T: type, field: *T, label: []const u8, options: FieldOptions) !void {
        const row = try self.Row(label);
        const names = comptime std.meta.fieldNames(T);
        var choices: [names.len][]const u8 = undefined;
        inline for (names, 0..) |name, i| choices[i] = name;
        const dropdown = try Widgets.Dropdown(self.mEngineContext, .{ .Entity = row }, &choices, ChoiceOf(T, field.*), self.mOptions);
        try self.Bind(dropdown, field, AccessFor(T), options.OnChange, null, options.Rebuilds);
    }

    pub fn Vec2Field(self: *Builder, field: *Vec2(f32), label: []const u8, options: NumberOptions) !void {
        try self.Vector(2, @ptrCast(field), label, options);
    }

    pub fn Vec3Field(self: *Builder, field: *Vec3(f32), label: []const u8, options: NumberOptions) !void {
        try self.Vector(3, @ptrCast(field), label, options);
    }

    pub fn Vec4Field(self: *Builder, field: *Vec4(f32), label: []const u8, options: NumberOptions) !void {
        try self.Vector(4, @ptrCast(field), label, options);
    }

    /// Red, green, blue and alpha, each 0 to 1, and a swatch of the color
    pub fn Color(self: *Builder, field: *Vec4(f32), label: []const u8, options: FieldOptions) !void {
        const row = try self.Row(label);
        const color_field = try Widgets.ColorField(self.mEngineContext, .{ .Entity = row }, field.*, self.mOptions);
        try self.Bind(color_field, field, AccessFor(Vec4(f32)), options.OnChange, null, options.Rebuilds);
    }

    /// A line of text typed into, kept when Enter is pressed or the field is left
    pub fn Text(self: *Builder, field: *std.ArrayList(u8), label: []const u8, options: FieldOptions) !void {
        const row = try self.Row(label);
        const text_field = try Widgets.TextField(self.mEngineContext, .{ .Entity = row }, field.items);
        //the text, which TextSubmitted is sent from
        try self.Bind(UIManager.LabelOf(text_field).?, field, AccessFor(std.ArrayList(u8)), options.OnChange, null, options.Rebuilds);
    }

    /// A struct inside the component: its own UIRender's rows, under a header with `label` that folds them away. A struct
    /// without a UIRender shows nothing
    pub fn Struct(self: *Builder, field: anytype, label: []const u8) !void {
        const T = @typeInfo(@TypeOf(field)).pointer.child;
        if (!@hasDecl(T, "UIRender")) return;
        const section = try Widgets.CollapsingHeader(self.mEngineContext, .{ .Entity = self.mParent }, label, true, self.mOptions);
        var inner = self.*;
        inner.mParent = section.Content.?;
        try field.UIRender(&inner);
    }

    /// A line of text that isn't a field: a note about the ones around it
    pub fn Note(self: *Builder, text: []const u8) !void {
        _ = try Widgets.Label(self.mEngineContext, .{ .Entity = self.mParent }, text);
    }

    pub fn Separator(self: *Builder) !void {
        _ = try Widgets.Separator(self.mEngineContext, .{ .Entity = self.mParent });
    }

    fn Number(self: *Builder, comptime T: type, field: *T, label: []const u8, options: NumberOptions) !void {
        const row = try self.Row(label);
        const kept: f64 = switch (T) {
            f32 => field.*,
            else => @floatFromInt(field.*),
        };
        const shown = if (options.Convert) |convert| convert.ToShown(kept) else kept;
        var value: EntityComponents.AttribComponent.ValueTypes = switch (T) {
            f32 => .{ .float32 = 0 },
            i32 => .{ .int32 = 0 },
            //no attribute is a byte: shown as a u32, and kept to a byte when written
            u32, u8 => .{ .uint32 = 0 },
            else => @compileError("Not a number field type: " ++ @typeName(T)),
        };
        value.SetFromFloat(shown);
        const number_field = try Widgets.NumberField(self.mEngineContext, .{ .Entity = row }, value, .{
            .mSpeed = options.Speed,
            .mMin = options.Min,
            .mMax = options.Max,
            .mDecimals = options.Decimals,
        });
        try self.Bind(number_field, field, AccessFor(T), options.OnChange, options.Convert, false);
    }

    fn Vector(self: *Builder, comptime count: usize, field: *[count]f32, label: []const u8, options: NumberOptions) !void {
        const row = try self.Row(label);
        const number_row = try Widgets.NumberRow(self.mEngineContext, .{ .Entity = row }, field, .{
            .mSpeed = options.Speed,
            .mMin = options.Min,
            .mMax = options.Max,
            .mDecimals = options.Decimals,
        });
        //a binding for each number, to its own float of the vector
        var index: usize = 0;
        var children = number_row.GetIterator(.Child);
        while (children.next()) |child| {
            if (!child.HasComponent(EntityComponents.AttribComponent)) continue;
            try self.Bind(child, &field[index], AccessFor(f32), options.OnChange, options.Convert, false);
            index += 1;
        }
    }

    /// A row with the field's label, for the field's widget to go after
    fn Row(self: *Builder, label: []const u8) !Entity {
        const engine_context = self.mEngineContext;
        const row = try self.mParent.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
        try row.SetTranslation(engine_context, Vec3(f32){ .x = 0, .y = 0, .z = Widgets.DEPTH_STEP });
        _ = try row.AddComponent(engine_context, LayoutComponent{ .mDirection = .Row, .mGap = Widgets.PADDING, .mCrossAlign = .Center });
        _ = try row.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fill = 1 } });
        const shown_label = try Widgets.Label(engine_context, .{ .Entity = row }, label);
        shown_label.GetComponent(LayoutItemComponent).?.mWidth = .{ .Fixed = LABEL_WIDTH };
        return row;
    }

    /// Ties `widget` to `field`, which is inside the component this builds for
    fn Bind(self: *Builder, widget: Entity, field: anytype, access: *const Access, on_change: ?OnChange, convert: ?Conversion, rebuilds: bool) !void {
        const engine_context = self.mEngineContext;
        if (!widget.HasComponent(UIElementComponent)) _ = try widget.AddComponent(engine_context, UIElementComponent{});
        _ = try UIManager.ElementOf(widget).?.AddComponent(engine_context, FieldBindingComponent{
            .mObject = self.mObject,
            .mResolve = self.mResolve,
            .mOffset = @intFromPtr(field) - self.mBase,
            .mAccess = access,
            .mAfterEdit = self.mAfterEdit,
            .mOnChange = on_change,
            .mConvert = convert,
            .mRebuild = if (rebuilds) self.mRoot else null,
        });
    }
};

/// Builds the UI that edits `object`'s component of type `component_type` under `parent`: a header with the component's
/// name that folds away the rows its UIRender asks for. `root` is what is built again when a field that rebuilds is
/// edited (see BindingSystem.TakeRebuild). Returns the header's content, null for a component without a UIRender, which
/// shows nothing
pub fn BuildComponent(engine_context: *EngineContext, parent: Entity, root: Entity, object: anytype, comptime component_type: type, options: Widgets.Options) !?Entity {
    const zone = Tracy.ZoneInit("Inspector::BuildComponent", @src());
    defer zone.Deinit();
    if (!@hasDecl(component_type, "UIRender")) return null;
    if (!object.HasComponent(component_type)) return null;

    const section = try Widgets.CollapsingHeader(engine_context, .{ .Entity = parent }, component_type.Name, true, options);
    try RenderComponent(engine_context, section.Content.?, root, object, component_type, options);
    return section.Content.?;
}

/// The rows `object`'s component of type `component_type` asks for (its UIRender), under `parent`, with no header.
/// UIRender is handed a copy of the component, which its field offsets are measured from: making widgets adds
/// components to ECSs, and when that is the ECS the component is in (a UI element's own components are in the
/// UIManager's, like the widgets' styles) it can move in memory part way through. The bindings find the real one
pub fn RenderComponent(engine_context: *EngineContext, parent: Entity, root: Entity, object: anytype, comptime component_type: type, options: Widgets.Options) !void {
    try RenderComponentWith(engine_context, parent, root, object, component_type, options, null);
}

/// RenderComponent, and after the component's own rows (if it has a UIRender) `extras.After(component_type, builder,
/// component, object)`, for rows that need the object rather than only the component: `extras` is whoever built the
/// inspector, or null. The component it is handed is the copy the rows were built from
pub fn RenderComponentWith(engine_context: *EngineContext, parent: Entity, root: Entity, object: anytype, comptime component_type: type, options: Widgets.Options, extras: anytype) !void {
    const zone = Tracy.ZoneInit("Inspector::RenderComponent", @src());
    defer zone.Deinit();
    const component = object.GetComponent(component_type) orelse return;
    const copy = try engine_context.FrameAllocator().create(component_type);
    copy.* = component.*;
    var builder = ForComponent(engine_context, parent, root, object, component_type, options);
    builder.mBase = @intFromPtr(copy);
    if (comptime @hasDecl(component_type, "UIRender")) try copy.UIRender(&builder);
    if (comptime @TypeOf(extras) != @TypeOf(null)) try extras.After(component_type, &builder, copy, object);
}

/// A Builder for `object`'s component of type `component_type`, putting its rows under `parent`, its field offsets
/// measured from the component where it is now. For calling the Builder's fields directly, when building can't move
/// the component (see RenderComponent)
pub fn ForComponent(engine_context: *EngineContext, parent: Entity, root: Entity, object: anytype, comptime component_type: type, options: Widgets.Options) Builder {
    const component = object.GetComponent(component_type).?;
    return .{
        .mEngineContext = engine_context,
        .mParent = parent,
        .mRoot = root,
        .mObject = ObjectRef.Of(object),
        .mBase = @intFromPtr(component),
        .mResolve = ResolveFor(@TypeOf(object), component_type),
        .mAfterEdit = AfterEditFor(@TypeOf(object), component_type),
        .mOptions = options,
    };
}

/// Finds an object's component of one type again: null once the object or its component has gone
fn ResolveFor(comptime object_type: type, comptime component_type: type) *const fn (ObjectRef) ?*anyopaque {
    return &struct {
        fn Resolve(object: ObjectRef) ?*anyopaque {
            const typed = @field(object, ObjectTag(object_type));
            if (!typed.IsActive()) return null;
            return @ptrCast(typed.GetComponent(component_type) orelse return null);
        }
    }.Resolve;
}

/// What has to happen after a component of one type is edited, the edits going straight into its fields: a transform's
/// world transform worked out again, a layout setting laid out again, a rigid body kept in step with its mass
fn AfterEditFor(comptime object_type: type, comptime component_type: type) *const fn (*EngineContext, ObjectRef) anyerror!void {
    return &struct {
        fn AfterEdit(engine_context: *EngineContext, object: ObjectRef) anyerror!void {
            //a scroll or popup setting changes how the element's entity is laid out
            if (object_type == UIElement) {
                if (component_type != ScrollComponent and component_type != PopupComponent) return;
                const element = object.UIElement;
                if (!element.IsActive()) return;
                const owner = element.GetOwner();
                if (owner.IsActive()) try owner.MarkLayoutDirty(engine_context);
                return;
            }
            if (object_type != Entity) return;
            const entity = object.Entity;
            if (!entity.IsActive()) return;
            if (component_type == TransformComponent) {
                try entity.MarkTransformDirty(engine_context);
                //x and y of something layout places snap back, z stays editable
                if (LayoutSystem.IsPlacedByLayout(entity)) try entity.MarkLayoutDirty(engine_context);
            }
            if (component_type == LayoutComponent or component_type == LayoutItemComponent or component_type == TextComponent) {
                try entity.MarkLayoutDirty(engine_context);
            }
            if (component_type == RigidBodyComponent) try entity.SyncRigidBody(engine_context);
        }
    }.AfterEdit;
}

fn ObjectTag(comptime object_type: type) []const u8 {
    return switch (object_type) {
        Entity => "Entity",
        Scene => "Scene",
        Player => "Player",
        GameContext => "GameContext",
        Bus => "Bus",
        UIElement => "UIElement",
        else => @compileError("Not an object type: " ++ @typeName(object_type)),
    };
}

/// Reading and writing a field of type T, as a Value
pub fn AccessFor(comptime T: type) *const Access {
    return &struct {
        const access = Access{ .Read = Read, .Write = Write };

        fn Read(field: *anyopaque) Value {
            const value: *T = @ptrCast(@alignCast(field));
            return switch (T) {
                f32 => .{ .Number = value.* },
                i32, u32, u8 => .{ .Number = @floatFromInt(value.*) },
                bool => .{ .Bool = value.* },
                Vec4(f32) => .{ .Color = value.* },
                Quat(f32) => .{ .Rotation = value.* },
                AssetHandle => .{ .Asset = value.* },
                std.ArrayList(u8) => .{ .Text = value.items },
                else => .{ .Choice = ChoiceOf(T, value.*) orelse 0 },
            };
        }

        fn Write(engine_context: *EngineContext, field: *anyopaque, written: Value) anyerror!void {
            const value: *T = @ptrCast(@alignCast(field));
            switch (T) {
                f32 => value.* = @floatCast(written.Number),
                i32 => value.* = @intFromFloat(std.math.clamp(@round(written.Number), std.math.minInt(i32), std.math.maxInt(i32))),
                u32 => value.* = @intFromFloat(std.math.clamp(@round(written.Number), 0, std.math.maxInt(u32))),
                u8 => value.* = @intFromFloat(std.math.clamp(@round(written.Number), 0, std.math.maxInt(u8))),
                bool => value.* = written.Bool,
                Vec4(f32) => value.* = written.Color,
                Quat(f32) => value.* = written.Rotation,
                //the written handle comes with a reference of its own, which the field takes over
                AssetHandle => {
                    value.ReleaseAsset();
                    value.* = written.Asset;
                },
                std.ArrayList(u8) => {
                    value.clearRetainingCapacity();
                    try value.appendSlice(engine_context.EngineAllocator(), written.Text);
                },
                else => {
                    const values = comptime std.enums.values(T);
                    if (written.Choice < values.len) value.* = values[written.Choice];
                },
            }
        }
    }.access;
}

/// How big an asset field's thumbnail is, and the longest a readout's text is
const THUMBNAIL_SIZE: f32 = 32;
const READOUT_LEN = 64;

/// A number's options with OnChange set, if it isn't already
fn MergeOnChange(options: NumberOptions, on_change: ?OnChange) NumberOptions {
    var merged = options;
    if (merged.OnChange == null) merged.OnChange = on_change;
    return merged;
}

/// Which case a union is in, by its place among the cases
fn CaseOf(comptime U: type, value: U) usize {
    return @intFromEnum(std.meta.activeTag(value));
}

/// A union's case, as a Choice: picking another starts it at its default (see Builder.Union)
fn UnionCaseAccess(comptime U: type) *const Access {
    return &struct {
        const access = Access{ .Read = Read, .Write = Write };
        const Tag = std.meta.Tag(U);

        fn Read(field: *anyopaque) Value {
            const value: *U = @ptrCast(@alignCast(field));
            return .{ .Choice = CaseIndex(std.meta.activeTag(value.*)) };
        }

        fn Write(_: *EngineContext, field: *anyopaque, written: Value) anyerror!void {
            const value: *U = @ptrCast(@alignCast(field));
            if (written.Choice == CaseIndex(std.meta.activeTag(value.*))) return;
            const names = comptime @typeInfo(U).@"union".field_names;
            const types = comptime @typeInfo(U).@"union".field_types;
            inline for (names, types, 0..) |name, P, i| {
                if (written.Choice == i) {
                    value.* = if (comptime @hasDecl(U, "DefaultFor")) U.DefaultFor(@field(Tag, name)) else @unionInit(U, name, PayloadDefault(P));
                }
            }
        }

        fn CaseIndex(tag: Tag) usize {
            inline for (@typeInfo(U).@"union".field_names, 0..) |name, i| {
                if (tag == @field(Tag, name)) return i;
            }
            unreachable;
        }
    }.access;
}

/// What a union case starts at when it is picked, without a DefaultFor: the type's `default` if it has one, else its
/// fields' defaults (zero where they have none)
fn PayloadDefault(comptime P: type) P {
    if (P == void) return {};
    switch (@typeInfo(P)) {
        .@"struct", .@"union", .@"enum" => if (@hasDecl(P, "default")) return P.default,
        else => {},
    }
    if (@typeInfo(P) == .@"struct") return std.mem.zeroInit(P, .{});
    return std.mem.zeroes(P);
}

/// One bit of a bit set, as a Bool
fn BitAccess(comptime T: type, comptime bit: usize) *const Access {
    return &struct {
        const access = Access{ .Read = Read, .Write = Write };

        fn Read(field: *anyopaque) Value {
            const value: *T = @ptrCast(@alignCast(field));
            return .{ .Bool = value.isSet(bit) };
        }

        fn Write(_: *EngineContext, field: *anyopaque, written: Value) anyerror!void {
            const value: *T = @ptrCast(@alignCast(field));
            value.setValue(bit, written.Bool);
        }
    }.access;
}

/// A field shown as `show` writes it, as Text, never written. The text is in a buffer of its own, which the binding
/// system puts on the label as soon as it reads it
fn ReadoutAccess(comptime T: type, comptime show: anytype) *const Access {
    return &struct {
        const access = Access{ .Read = Read, .Write = Write };
        var buffer: [READOUT_LEN]u8 = undefined;

        fn Read(field: *anyopaque) Value {
            const value: *T = @ptrCast(@alignCast(field));
            return .{ .Text = show(value.*, &buffer) };
        }

        fn Write(_: *EngineContext, _: *anyopaque, _: Value) anyerror!void {}
    }.access;
}

/// An optional number's checkbox: whether it has a number. Ticked, it starts at 0
const OPTIONAL_SET = Access{
    .Read = struct {
        fn Read(field: *anyopaque) Value {
            const value: *?f32 = @ptrCast(@alignCast(field));
            return .{ .Bool = value.* != null };
        }
    }.Read,
    .Write = struct {
        fn Write(_: *EngineContext, field: *anyopaque, written: Value) anyerror!void {
            const value: *?f32 = @ptrCast(@alignCast(field));
            if (written.Bool == (value.* != null)) return;
            value.* = if (written.Bool) 0 else null;
        }
    }.Write,
};

/// An optional number's number, 0 while it has none. Only written while it has one
const OPTIONAL_VALUE = Access{
    .Read = struct {
        fn Read(field: *anyopaque) Value {
            const value: *?f32 = @ptrCast(@alignCast(field));
            return .{ .Number = value.* orelse 0 };
        }
    }.Read,
    .Write = struct {
        fn Write(_: *EngineContext, field: *anyopaque, written: Value) anyerror!void {
            const value: *?f32 = @ptrCast(@alignCast(field));
            if (value.* != null) value.* = @floatCast(written.Number);
        }
    }.Write,
};

/// An entity or scene field's object's name, never written
fn NameAccess(comptime T: type) *const Access {
    return &struct {
        const access = Access{ .Read = Read, .Write = Write };

        fn Read(field: *anyopaque) Value {
            const object: *T = @ptrCast(@alignCast(field));
            return .{ .Text = NameOf(object.*) };
        }

        fn Write(_: *EngineContext, _: *anyopaque, _: Value) anyerror!void {}
    }.access;
}

/// An entity's or scene's name: "None" for none, up to the first 0 if it was saved with one
fn NameOf(object: anytype) []const u8 {
    if (object.mID == @TypeOf(object).NullObject or !object.IsActive()) return "None";
    const name = (object.GetComponent(NameComponent) orelse return @typeName(@TypeOf(object))).mName.items;
    return name[0 .. std.mem.indexOfScalar(u8, name, 0) orelse name.len];
}

/// Where an enum's value is among its values
fn ChoiceOf(comptime T: type, value: T) ?usize {
    for (std.enums.values(T), 0..) |each, i| {
        if (each == value) return i;
    }
    return null;
}
