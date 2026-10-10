//! Builders for the common widgets: each makes an entity tree out of the primitives (quads, text, layout, styles, and
//! for some a stock script) under a parent, and hands back its root. A widget isn't anything to the engine once it is
//! made: a button is a styled quad with a label, and what it does is whatever script is put on it.
//! Built in code for now, which is easy to test. Once these settle, saving one as a template file is a single call, and
//! templates can take over.
//! Every entity a builder makes inside another sits DEPTH_STEP in front of it. Layout never sets depth, and two shapes at
//! the same depth are the same distance from the camera, where the renderer keeps whichever it finds first: a button's
//! quad could hide behind the panel it is on, a label behind its button.
const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const Player = @import("../ECSObjects/Player.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const AssetHandle = @import("../ECSObjects/AssetHandle.zig");
const UIManager = @import("UIManager.zig");
const NumberFieldSystem = @import("NumberFieldSystem.zig");
const ScrollSystem = @import("ScrollSystem.zig");
const WidgetActions = @import("WidgetActions.zig");
const Layout = @import("Layout.zig");
const MathTypes = @import("../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;
const Vec4 = MathTypes.Vec4;

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const ShapeComponent = EntityComponents.ShapeComponent;
const SurfaceComponent = EntityComponents.SurfaceComponent;
const TextComponent = EntityComponents.TextComponent;
const LayoutComponent = EntityComponents.LayoutComponent;
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const AttribComponent = EntityComponents.AttribComponent;
const EntitySceneComponent = EntityComponents.EntitySceneComponent;
const UIComponents = @import("../ECSComponents/UIComponents.zig");
const NumberFieldComponent = UIComponents.NumberFieldComponent;
const TextInputComponent = UIComponents.TextInputComponent;
const PopupComponent = UIComponents.PopupComponent;
const PopupRefComponent = UIComponents.PopupRefComponent;
const SelectionGroupComponent = UIComponents.SelectionGroupComponent;
const FloatingWindowComponent = UIComponents.FloatingWindowComponent;
const UIElementComponent = EntityComponents.UIElementComponent;

/// What a widget is made under: an entity, or the top of a scene
pub const Parent = union(enum) {
    Entity: Entity,
    Scene: Scene,
};

/// For the widgets that come with a stock script
pub const Options = struct {
    /// whether to put the stock script on it. Off for building one without compiling its script, e.g. in a test
    StockScripts: bool = true,
};

/// The stock widget scripts (EngineAssets/scripts/UI/), each a hook calling one of WidgetActions
pub const StockScript = enum {
    Toggle,
    Select,
    OpenPopup,
    OpenContextMenu,
    ClosePopups,
    Collapse,
    Choose,
    ColorField,
    Fold,
    FoldArrow,
    MenuItem,
    Submenu,
    MenuBarMenu,
    Divider,
    Tab,
    Window,
    WindowTitle,
    CloseWindow,

    pub fn Path(self: StockScript) []const u8 {
        return switch (self) {
            inline else => |script| "src/Imaginengion/EngineAssets/scripts/UI/" ++ @tagName(script) ++ ".zig",
        };
    }
};

/// The font size widgets' text is made at
pub const TEXT_SIZE: f32 = 16;
/// The room between a button's or row's edge and what is in it
pub const PADDING: f32 = 6;
/// How far in front of its parent each entity a builder makes sits, in its parent's units (canvas units in an overlay).
/// Any step separates them; this one is far too small to see
pub const DEPTH_STEP: f32 = 0.01;
/// A checkbox's box
pub const CHECKBOX_SIZE: f32 = 16;
/// How far in front of the rest of its scene a dropdown's list or a menu is, so it is drawn over what it hangs over:
/// in front of the floating windows too (WidgetActions.WINDOW_DEPTH), as many as a scene is likely to have. The overlay
/// is drawn in perspective, so something this far in front is drawn a little bigger, about 0.3%
pub const POPUP_DEPTH: f32 = 3;
/// How thick a split's divider is: thick enough to grab
pub const DIVIDER_SIZE: f32 = 8;
/// A floating window's title bar's height, and the size of its close button
pub const TITLE_SIZE: f32 = 22;

/// What Split makes
pub const SplitParts = struct {
    /// what goes in the split's parent
    Root: Entity,
    /// left or top
    First: Entity,
    Divider: Entity,
    /// right or bottom
    Second: Entity,
};

/// Which of a split's panes keeps its size as the split's parent changes size
pub const FixedPane = enum { First, Second };

/// What FloatingWindow makes
pub const WindowParts = struct {
    /// the whole window, at the top of its scene
    Window: Entity,
    TitleBar: Entity,
    /// where what is in the window goes
    Content: Entity,
};
/// A color field's swatch
pub const SWATCH_SIZE: f32 = 20;
/// A folding header's arrow box, and the room a leaf tree node leaves where one would be
pub const ARROW_SIZE: f32 = 16;
/// How far a tree node's children sit in from it
pub const INDENT: f32 = 16;
/// A checkable menu item's check box
pub const MENU_CHECK_SIZE: f32 = 10;
/// About how tall a menu row is: a line of text (a little more than its font size) and the row's padding. Only for
/// sizing a ScrollingMenu, so being a little off shows part of a row, which hints there is more
pub const MENU_ROW_HEIGHT: f32 = TEXT_SIZE * 1.25 + PADDING;

/// What TreeNode and CollapsingHeader make
pub const Fold = struct {
    /// a tree node's whole tree, its header and content: what goes in its parent. The header for a collapsing header
    Node: Entity,
    /// the row that is clicked
    Header: Entity,
    /// where what it folds goes. Null for a leaf tree node, which folds nothing
    Content: ?Entity,
};

pub const TreeNodeOptions = struct {
    /// a node with nothing under it: no arrow and no content
    Leaf: bool = false,
    /// whether its content starts out shown
    Open: bool = false,
    StockScripts: bool = true,
};

pub const MenuItemOptions = struct {
    /// a shortcut's name shown at the right, e.g. "Ctrl+S". Only shown: the shortcut itself is handled wherever keys are
    Shortcut: ?[]const u8 = null,
    /// a check box at the right, checked with WidgetActions.SetChecked
    Checkable: bool = false,
    StockScripts: bool = true,
};

/// Gives `entity` a quad shape painted with `surface`: every widget's background, box and bar
pub fn AddQuad(engine_context: *EngineContext, entity: Entity, quad: ShapeComponent.Quad, surface: SurfaceComponent) !void {
    _ = try entity.AddComponent(engine_context, ShapeComponent.MakeQuad(quad));
    _ = try entity.AddComponent(engine_context, surface);
}

/// A line of text, sized to fit it. Style "Text"
pub fn Label(engine_context: *EngineContext, parent: Parent, text: []const u8) !Entity {
    const entity = try NewEntity(engine_context, parent);
    var text_component = TextComponent{ .mFontSize = TEXT_SIZE };
    try text_component.SetText(engine_context, text);
    _ = try entity.AddComponent(engine_context, text_component);
    _ = try entity.AddComponent(engine_context, SurfaceComponent{});
    _ = try entity.AddComponent(engine_context, LayoutItemComponent{});
    try UIManager.Style(engine_context, entity, "Text");
    return entity;
}

/// A column filling what it is in, with room around its edges, whose content scrolls with a scrollbar when it runs past
/// the bottom, cut off by a mask the shape of the area: a panel's or a window's content. The mask's shape has no
/// surface, so it isn't drawn, and layout keeps it the area's size
pub fn ScrollArea(engine_context: *EngineContext, parent: Parent) !Entity {
    const area = try NewEntity(engine_context, parent);
    _ = try area.AddComponent(engine_context, LayoutComponent{ .mDirection = .Column, .mPadding = .All(PADDING) });
    _ = try area.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fill = 1 }, .mHeight = .{ .Fill = 1 } });
    _ = try area.AddComponent(engine_context, ShapeComponent{});
    _ = try area.AddComponent(engine_context, EntityComponents.MaskComponent{});
    _ = try area.AddComponent(engine_context, UIElementComponent{});
    _ = try UIManager.ElementOf(area).?.AddComponent(engine_context, UIComponents.ScrollComponent{ .mScroll = .Vertical });
    return area;
}

/// A box showing a line of text, as wide as what it is in, that what drags one of `accepts` can be dropped on (a drop
/// target for those components): a file from the Content Browser (FileRefComponent), an object's row from a hierarchy
/// panel (ObjectRefComponent). An asset or reference field. Style "Field"
pub fn DropBox(engine_context: *EngineContext, parent: Parent, text: []const u8, comptime accepts: []const type) !Entity {
    const box = try NewEntity(engine_context, parent);
    try AddQuad(engine_context, box, .{}, .{});
    _ = try box.AddComponent(engine_context, LayoutComponent{
        .mDirection = .Row,
        .mPadding = .{ .Left = PADDING, .Right = PADDING, .Top = PADDING / 2, .Bottom = PADDING / 2 },
        .mCrossAlign = .Center,
    });
    _ = try box.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fill = 1 } });
    _ = try box.AddComponent(engine_context, EntityComponents.DropTargetComponent.Accepting(accepts));
    try UIManager.Style(engine_context, box, "Field");
    _ = try Label(engine_context, .{ .Entity = box }, text);
    return box;
}

/// A quad filling what it is in that shows `player`'s view, its render target (ViewportComponent), instead of a texture:
/// a camera's view in a panel. Whoever renders the player sizes its view to the quad (Viewports.FitPlayerToQuad)
pub fn Viewport(engine_context: *EngineContext, parent: Parent, player: Player) !Entity {
    const quad = try NewEntity(engine_context, parent);
    try AddQuad(engine_context, quad, .{}, .{});
    _ = try quad.AddComponent(engine_context, EntityComponents.ViewportComponent{ .mPlayer = player });
    _ = try quad.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fill = 1 }, .mHeight = .{ .Fill = 1 } });
    return quad;
}

/// A grid as wide as what it is in, putting as many of its children side by side as fit and wrapping onto new rows,
/// with `gap` between them both ways: e.g. Tiles
pub fn Grid(engine_context: *EngineContext, parent: Parent, gap: f32) !Entity {
    const grid = try NewEntity(engine_context, parent);
    _ = try grid.AddComponent(engine_context, LayoutComponent{ .mDirection = .Grid, .mGap = gap, .mColumns = .Auto });
    _ = try grid.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fill = 1 } });
    return grid;
}

/// A square image with a line of text under it, in a box `width` wide that lights up when hovered (style "Header"):
/// a file in a file browser, an item in an inventory. It does nothing when clicked: what it does is up to whoever made it
pub fn Tile(engine_context: *EngineContext, parent: Parent, texture: AssetHandle, text: []const u8, width: f32) !Entity {
    const tile = try NewEntity(engine_context, parent);
    try AddQuad(engine_context, tile, .{}, .{});
    _ = try tile.AddComponent(engine_context, LayoutComponent{ .mDirection = .Column, .mPadding = .All(PADDING / 2), .mGap = PADDING / 2, .mCrossAlign = .Center });
    _ = try tile.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fixed = width } });
    try UIManager.Style(engine_context, tile, "Header");
    const image_size = width - PADDING;
    _ = try Image(engine_context, .{ .Entity = tile }, texture, .{ .x = image_size, .y = image_size });
    _ = try Label(engine_context, .{ .Entity = tile }, text);
    return tile;
}

/// A row to put things in side by side, e.g. buttons, with a gap between them. As big as what is in it
pub fn Row(engine_context: *EngineContext, parent: Parent) !Entity {
    const row = try NewEntity(engine_context, parent);
    _ = try row.AddComponent(engine_context, LayoutComponent{ .mDirection = .Row, .mGap = PADDING, .mCrossAlign = .Center });
    _ = try row.AddComponent(engine_context, LayoutItemComponent{});
    return row;
}

/// A column to put things in one under the other, as wide as what it is in and as tall as what is in it
pub fn Column(engine_context: *EngineContext, parent: Parent) !Entity {
    const column = try NewEntity(engine_context, parent);
    _ = try column.AddComponent(engine_context, LayoutComponent{ .mDirection = .Column });
    _ = try column.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fill = 1 } });
    return column;
}

/// A box with a background, `size` big, to put other widgets in one under the other with a gap between them: a menu
/// screen, a corner of a HUD. What doesn't fit runs over its edges. Style "Window"
pub fn Panel(engine_context: *EngineContext, parent: Parent, size: Vec2(f32)) !Entity {
    const panel = try NewEntity(engine_context, parent);
    try AddQuad(engine_context, panel, .{}, .{});
    _ = try panel.AddComponent(engine_context, LayoutComponent{ .mDirection = .Column, .mGap = PADDING, .mPadding = .All(PADDING) });
    _ = try panel.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fixed = size.x }, .mHeight = .{ .Fixed = size.y } });
    try UIManager.Style(engine_context, panel, "Window");
    return panel;
}

/// A column of lines of text, one under the other, as wide as what it is in: for SyncLines to keep showing a list
pub fn Lines(engine_context: *EngineContext, parent: Parent) !Entity {
    const lines = try NewEntity(engine_context, parent);
    _ = try lines.AddComponent(engine_context, LayoutComponent{ .mDirection = .Column });
    _ = try lines.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fill = 1 } });
    return lines;
}

/// Keeps a column of lines (made by Lines) showing `lines`, in order: a label made for each one it is short of and the
/// spare ones deleted, and a label's text only set when it is different. A list that hasn't changed costs a comparison
pub fn SyncLines(engine_context: *EngineContext, column: Entity, lines: []const []const u8) !void {
    var labels: std.ArrayList(Entity) = .empty;
    var children = column.GetIterator(.Child);
    while (children.next()) |child| try labels.append(engine_context.FrameAllocator(), child);

    for (lines, 0..) |line, i| {
        if (i < labels.items.len) {
            try WidgetActions.SetText(engine_context, labels.items[i], line);
        } else {
            _ = try Label(engine_context, .{ .Entity = column }, line);
        }
    }
    if (labels.items.len > lines.len) {
        for (labels.items[lines.len..]) |spare| try spare.Delete(engine_context);
        try column.MarkLayoutDirty(engine_context);
    }
}

/// A thin line across whatever it is in. Style "Separator"
pub fn Separator(engine_context: *EngineContext, parent: Parent) !Entity {
    const entity = try NewEntity(engine_context, parent);
    try AddQuad(engine_context, entity, .{}, .{});
    _ = try entity.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fill = 1 }, .mHeight = .{ .Fixed = 1 } });
    try UIManager.Style(engine_context, entity, "Separator");
    return entity;
}

/// A texture shown at `size`. The image takes its own reference to the texture
pub fn Image(engine_context: *EngineContext, parent: Parent, texture: AssetHandle, size: Vec2(f32)) !Entity {
    const entity = try NewEntity(engine_context, parent);
    texture.RetainAsset();
    try AddQuad(engine_context, entity, .{}, .{ .mTexture = texture });
    _ = try entity.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fixed = size.x }, .mHeight = .{ .Fixed = size.y } });
    return entity;
}

/// A quad that fits a label with room around it. Style "Button", so it lights up when hovered and pressed. It does
/// nothing when clicked: what it does is the OnPointerEventScript put on it
pub fn Button(engine_context: *EngineContext, parent: Parent, text: []const u8) !Entity {
    const button = try ButtonFrame(engine_context, parent);
    _ = try Label(engine_context, .{ .Entity = button }, text);
    return button;
}

/// Button, with an image in it instead of a label
pub fn ImageButton(engine_context: *EngineContext, parent: Parent, texture: AssetHandle, size: Vec2(f32)) !Entity {
    const button = try ButtonFrame(engine_context, parent);
    _ = try Image(engine_context, .{ .Entity = button }, texture, size);
    return button;
}

/// A box and a label in a row. Clicking the box checks or unchecks it (the stock Toggle script): checked is SelectedTag
/// on the box, the row's first child, which the theme's "Checkbox" Selected color shows. Each click sends the box and
/// everything it is inside a ValueChanged
pub fn Checkbox(engine_context: *EngineContext, parent: Parent, text: []const u8, options: Options) !Entity {
    const row = try NewEntity(engine_context, parent);
    _ = try row.AddComponent(engine_context, LayoutComponent{ .mDirection = .Row, .mGap = PADDING, .mCrossAlign = .Center });
    _ = try row.AddComponent(engine_context, LayoutItemComponent{});

    const box = try NewEntity(engine_context, .{ .Entity = row });
    try AddQuad(engine_context, box, .{}, .{});
    _ = try box.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fixed = CHECKBOX_SIZE }, .mHeight = .{ .Fixed = CHECKBOX_SIZE } });
    try UIManager.Style(engine_context, box, "Checkbox");
    if (options.StockScripts) try AddStockScript(engine_context, box, .Toggle);

    _ = try Label(engine_context, .{ .Entity = row }, text);
    return row;
}

/// A row of a list, as wide as the list, holding a label. Clicking it selects it and unselects its siblings (the stock
/// Select script), so only one row of a list is selected. Selected is SelectedTag, which the theme's "Header" Selected
/// color shows. Selecting it sends the row and everything it is inside a ValueChanged
pub fn SelectableRow(engine_context: *EngineContext, parent: Parent, text: []const u8, options: Options) !Entity {
    return SelectableRowWith(engine_context, parent, text, if (options.StockScripts) .Select else null);
}

/// SelectableRow, with `script` as what clicking it does
fn SelectableRowWith(engine_context: *EngineContext, parent: Parent, text: []const u8, script: ?StockScript) !Entity {
    const row = try NewEntity(engine_context, parent);
    try AddQuad(engine_context, row, .{}, .{});
    _ = try row.AddComponent(engine_context, LayoutComponent{
        .mDirection = .Row,
        .mPadding = .{ .Left = PADDING, .Right = PADDING, .Top = PADDING / 2, .Bottom = PADDING / 2 },
        .mCrossAlign = .Center,
    });
    _ = try row.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fill = 1 } });
    try UIManager.Style(engine_context, row, "Header");
    if (script) |stock| try AddStockScript(engine_context, row, stock);

    _ = try Label(engine_context, .{ .Entity = row }, text);
    return row;
}

/// A field showing a number, `value`, which dragging it sideways changes and a double click lets the player type, with
/// `settings` for how (speed, limits, decimals). It takes up the width it is given. The value is the field's
/// AttribComponent, which the number field system keeps its text showing, and every change sends the field and
/// everything it is inside a ValueChanged. Style "Field", its text style "Text"
pub fn NumberField(engine_context: *EngineContext, parent: Parent, value: AttribComponent.ValueTypes, settings: NumberFieldComponent) !Entity {
    const field = try NewEntity(engine_context, parent);
    try AddQuad(engine_context, field, .{}, .{});
    _ = try field.AddComponent(engine_context, LayoutComponent{
        .mDirection = .Row,
        .mPadding = .{ .Left = PADDING, .Right = PADDING, .Top = PADDING / 2, .Bottom = PADDING / 2 },
        .mMainAlign = .Center,
        .mCrossAlign = .Center,
    });
    _ = try field.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fill = 1 } });
    _ = try field.AddComponent(engine_context, AttribComponent{ .mData = value });
    try UIManager.Style(engine_context, field, "Field");
    _ = try UIManager.ElementOf(field).?.AddComponent(engine_context, settings);

    //showing its value from the start, rather than from the number field system's first frame
    var buffer: [64]u8 = undefined;
    const text = try Label(engine_context, .{ .Entity = field }, NumberFieldSystem.Format(&buffer, value, settings.mDecimals));
    _ = try UIManager.ElementOf(text).?.AddComponent(engine_context, TextInputComponent{ .mFocusOn = .DoubleClick });
    return field;
}

/// A line of text the player types into (a press on it starts typing), showing `text` to start with. Its text is a
/// child of it, which Enter or a press elsewhere sends TextSubmitted from. Takes up the width it is given. Style "Field",
/// its text style "Text"
pub fn TextField(engine_context: *EngineContext, parent: Parent, text: []const u8) !Entity {
    const field = try NewEntity(engine_context, parent);
    try AddQuad(engine_context, field, .{}, .{});
    _ = try field.AddComponent(engine_context, LayoutComponent{
        .mDirection = .Row,
        .mPadding = .{ .Left = PADDING, .Right = PADDING, .Top = PADDING / 2, .Bottom = PADDING / 2 },
        .mCrossAlign = .Center,
    });
    _ = try field.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fill = 1 } });
    try UIManager.Style(engine_context, field, "Field");
    const shown = try Label(engine_context, .{ .Entity = field }, text);
    _ = try UIManager.ElementOf(shown).?.AddComponent(engine_context, TextInputComponent{});
    return field;
}

/// 2 to 4 float number fields side by side, each after a box naming its axis (X, Y, Z, W, styles "AxisX" to "AxisW"):
/// a Vec2, Vec3 or Vec4. Its fields are its children with an AttribComponent, in order; a change to one sends the row
/// a ValueChanged whose mTarget is that field
pub fn NumberRow(engine_context: *EngineContext, parent: Parent, values: []const f32, settings: NumberFieldComponent) !Entity {
    std.debug.assert(values.len >= 2 and values.len <= 4);
    const row = try NewEntity(engine_context, parent);
    _ = try row.AddComponent(engine_context, LayoutComponent{ .mDirection = .Row, .mGap = PADDING / 2, .mCrossAlign = .Center });
    _ = try row.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fill = 1 } });

    const axes = [_][]const u8{ "X", "Y", "Z", "W" };
    const styles = [_][]const u8{ "AxisX", "AxisY", "AxisZ", "AxisW" };
    for (values, 0..) |value, i| {
        const axis = try NewEntity(engine_context, .{ .Entity = row });
        try AddQuad(engine_context, axis, .{}, .{});
        _ = try axis.AddComponent(engine_context, LayoutComponent{
            .mDirection = .Row,
            .mPadding = .{ .Left = PADDING, .Right = PADDING, .Top = PADDING / 2, .Bottom = PADDING / 2 },
            .mCrossAlign = .Center,
        });
        _ = try axis.AddComponent(engine_context, LayoutItemComponent{});
        try UIManager.Style(engine_context, axis, styles[i]);
        const letter = try Label(engine_context, .{ .Entity = axis }, axes[i]);
        //the axis style has the bold font and the text color as well
        try UIManager.Style(engine_context, letter, styles[i]);

        _ = try NumberField(engine_context, .{ .Entity = row }, .{ .float32 = value }, settings);
    }
    return row;
}

/// A button showing the current choice that opens a list of `choices` below it: picking one (the stock Choose script)
/// shows it on the button, closes the list, and sends the button and everything it is inside a ValueChanged. Read the
/// choice with WidgetActions.ChosenIndex or Chosen. The list is a popup at the top of the button's scene (a popup is
/// never inside what opens it), a little in front of the rest; its rows are SelectableRows, the choice being the
/// selected one. The button has style "Field" and the stock OpenPopup script, the list style "Popup"
pub fn Dropdown(engine_context: *EngineContext, parent: Parent, choices: []const []const u8, chosen: ?usize, options: Options) !Entity {
    const scene = SceneOf(parent);

    //the list: closed until the button opens it
    const list = try PopupList(engine_context, scene, PopupComponent{});
    for (choices, 0..) |choice, i| {
        const row = try SelectableRowWith(engine_context, .{ .Entity = list }, choice, if (options.StockScripts) .Choose else null);
        if (chosen == i) _ = try row.AddComponent(engine_context, EntityComponents.SelectedTag{});
    }

    //the button: the choice, and an arrow
    const button = try NewEntity(engine_context, parent);
    try AddQuad(engine_context, button, .{}, .{});
    _ = try button.AddComponent(engine_context, LayoutComponent{
        .mDirection = .Row,
        .mGap = PADDING,
        .mPadding = .{ .Left = PADDING, .Right = PADDING / 2, .Top = PADDING / 2, .Bottom = PADDING / 2 },
        .mCrossAlign = .Center,
    });
    _ = try button.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fill = 1 } });
    try UIManager.Style(engine_context, button, "Field");
    const shown = try Label(engine_context, .{ .Entity = button }, if (chosen) |i| choices[i] else "");
    shown.GetComponent(LayoutItemComponent).?.mWidth = .{ .Fill = 1 };
    //a letter for now: the font has no arrow glyph
    const arrow = try ButtonFrame(engine_context, .{ .Entity = button });
    arrow.GetComponent(LayoutComponent).?.mPadding = .{ .Left = PADDING / 2, .Right = PADDING / 2, .Top = 0, .Bottom = 0 };
    _ = try Label(engine_context, .{ .Entity = arrow }, "v");

    _ = try UIManager.ElementOf(button).?.AddComponent(engine_context, PopupRefComponent{ .mPopup = list });
    if (options.StockScripts) try AddStockScript(engine_context, button, .OpenPopup);
    return button;
}

/// Four number fields, red, green, blue and alpha (each 0 to 1), and a swatch showing the color they make. A change to
/// a channel recolors the swatch (the stock ColorField script) and sends the field and everything it is inside a
/// ValueChanged. Read the color with WidgetActions.ColorOf, set it with WidgetActions.SetColor. The swatch has style
/// "Swatch", which leaves its color alone
pub fn ColorField(engine_context: *EngineContext, parent: Parent, color: Vec4(f32), options: Options) !Entity {
    const row = try NewEntity(engine_context, parent);
    _ = try row.AddComponent(engine_context, LayoutComponent{ .mDirection = .Row, .mGap = PADDING / 2, .mCrossAlign = .Center });
    _ = try row.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fill = 1 } });

    const channel_settings = NumberFieldComponent{ .mSpeed = 0.005, .mMin = 0, .mMax = 1, .mDecimals = 3 };
    for ([_]f32{ color.x, color.y, color.z, color.w }) |channel| {
        _ = try NumberField(engine_context, .{ .Entity = row }, .{ .float32 = std.math.clamp(channel, 0, 1) }, channel_settings);
    }

    const swatch = try NewEntity(engine_context, .{ .Entity = row });
    try AddQuad(engine_context, swatch, .{}, .{});
    _ = try swatch.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fixed = SWATCH_SIZE }, .mHeight = .{ .Fixed = SWATCH_SIZE } });
    try UIManager.Style(engine_context, swatch, "Swatch");
    WidgetActions.UpdateSwatch(row);

    if (options.StockScripts) try AddStockScript(engine_context, row, .ColorField);
    return row;
}

/// The root of a tree of TreeNodes: a column whose rows are selected one at a time across the whole tree (a selection
/// group). Put the top nodes under it
pub fn Tree(engine_context: *EngineContext, parent: Parent) !Entity {
    const tree = try NewEntity(engine_context, parent);
    _ = try tree.AddComponent(engine_context, LayoutComponent{ .mDirection = .Column });
    _ = try tree.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fill = 1 } });
    _ = try tree.AddComponent(engine_context, UIElementComponent{});
    _ = try UIManager.ElementOf(tree).?.AddComponent(engine_context, SelectionGroupComponent{});
    return tree;
}

/// A node of a tree, like a row of the scene hierarchy: a header row (an arrow and a label) that clicking selects (the
/// stock Select script, one at a time across the tree it is in, see Tree), and under it its content, indented, which
/// the arrow folds away and out again (the stock FoldArrow script). Put its child nodes in Content. A leaf has a gap
/// where the arrow would be, and no content. The header has style "Header", its arrow box "Arrow"
pub fn TreeNode(engine_context: *EngineContext, parent: Parent, text: []const u8, options: TreeNodeOptions) !Fold {
    const node = try NewEntity(engine_context, parent);
    _ = try node.AddComponent(engine_context, LayoutComponent{ .mDirection = .Column });
    _ = try node.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fill = 1 } });

    const header = try FoldHeader(engine_context, .{ .Entity = node }, text, if (options.Leaf) null else options.Open);
    if (options.StockScripts) {
        try AddStockScript(engine_context, header, .Select);
        if (!options.Leaf) try AddStockScript(engine_context, FirstChild(header).?, .FoldArrow);
    }
    if (options.Leaf) return .{ .Node = node, .Header = header, .Content = null };

    const content = try FoldContent(engine_context, .{ .Entity = node }, options.Open, INDENT);
    return .{ .Node = node, .Header = header, .Content = content };
}

/// A header row (an arrow and a label) that clicking anywhere folds the content under it away and out again (the stock
/// Fold script): a section of a panel, like a component in the components panel. The header and its content both go in
/// `parent`, the content right after the header, so Node is the header. Style "Header"
pub fn CollapsingHeader(engine_context: *EngineContext, parent: Parent, text: []const u8, open: bool, options: Options) !Fold {
    const header = try FoldHeader(engine_context, parent, text, open);
    if (options.StockScripts) try AddStockScript(engine_context, header, .Fold);
    const content = try FoldContent(engine_context, parent, open, 0);
    return .{ .Node = header, .Header = header, .Content = content };
}

/// A row of menus along the top of a window. Put its menus in with Menu. Style "MenuBar"
pub fn MenuBar(engine_context: *EngineContext, parent: Parent) !Entity {
    const bar = try NewEntity(engine_context, parent);
    try AddQuad(engine_context, bar, .{}, .{});
    _ = try bar.AddComponent(engine_context, LayoutComponent{ .mDirection = .Row, .mPadding = .All(PADDING / 2) });
    _ = try bar.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fill = 1 } });
    try UIManager.Style(engine_context, bar, "MenuBar");
    return bar;
}

/// A menu of a menu bar: a button on the bar (style "Header") that opens the menu below it, and moving onto it while
/// another of the bar's menus is open switches to it (the stock MenuBarMenu script). Returns the menu, to put its items
/// in (MenuItem, Submenu, Separator)
pub fn Menu(engine_context: *EngineContext, bar: Entity, text: []const u8, options: Options) !Entity {
    const button = try NewEntity(engine_context, .{ .Entity = bar });
    try AddQuad(engine_context, button, .{}, .{});
    _ = try button.AddComponent(engine_context, LayoutComponent{ .mDirection = .Row, .mPadding = .{ .Left = PADDING, .Right = PADDING, .Top = PADDING / 2, .Bottom = PADDING / 2 }, .mCrossAlign = .Center });
    _ = try button.AddComponent(engine_context, LayoutItemComponent{});
    try UIManager.Style(engine_context, button, "Header");
    _ = try Label(engine_context, .{ .Entity = button }, text);

    const menu = try PopupList(engine_context, SceneOf(.{ .Entity = bar }), PopupComponent{});
    _ = try UIManager.ElementOf(button).?.AddComponent(engine_context, PopupRefComponent{ .mPopup = menu });
    if (options.StockScripts) try AddStockScript(engine_context, button, .MenuBarMenu);
    return menu;
}

/// An item of a menu: its text, then at the right the shortcut's name (style "TextDim") and a check box (style
/// "MenuCheck") if asked for. Clicking it closes every menu (the stock MenuItem script); what it does is the script put
/// on it. Greyed out and left alone by the pointer with DisabledTag. Style "Header"
pub fn MenuItem(engine_context: *EngineContext, menu: Entity, text: []const u8, options: MenuItemOptions) !Entity {
    const item = try MenuRow(engine_context, menu, text);
    if (options.Shortcut) |shortcut| {
        const shown = try Label(engine_context, .{ .Entity = item }, shortcut);
        try UIManager.Style(engine_context, shown, "TextDim");
    }
    if (options.Checkable) {
        const check = try NewEntity(engine_context, .{ .Entity = item });
        try AddQuad(engine_context, check, .{}, .{});
        _ = try check.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fixed = MENU_CHECK_SIZE }, .mHeight = .{ .Fixed = MENU_CHECK_SIZE } });
        try UIManager.Style(engine_context, check, "MenuCheck");
    }
    if (options.StockScripts) try AddStockScript(engine_context, item, .MenuItem);
    return item;
}

/// A row of a menu that opens another menu beside it, ending in an arrow: moving onto it or clicking it opens it (the
/// stock Submenu script). Returns the submenu, to put its items in. Style "Header"
pub fn Submenu(engine_context: *EngineContext, menu: Entity, text: []const u8, options: Options) !Entity {
    const row = try MenuRow(engine_context, menu, text);
    _ = try Label(engine_context, .{ .Entity = row }, WidgetActions.ARROW_FOLDED);
    //to the right of the row, top edges lined up
    const submenu = try PopupList(engine_context, SceneOf(.{ .Entity = menu }), PopupComponent{ .mPlacement = .{
        .Anchor = .{ .x = 1, .y = 1 },
        .Pivot = .{ .x = -1, .y = 1 },
    } });
    _ = try UIManager.ElementOf(row).?.AddComponent(engine_context, PopupRefComponent{ .mPopup = submenu });
    if (options.StockScripts) try AddStockScript(engine_context, row, .Submenu);
    return submenu;
}

/// A menu that right clicking `target` opens where the pointer is (the stock OpenContextMenu script, which keeps the
/// click, so a row's own menu wins over the panel's it is in). Returns the menu, to put its items in
pub fn ContextMenu(engine_context: *EngineContext, target: Entity, options: Options) !Entity {
    const menu = try NewContextMenu(engine_context, target);
    try ShareContextMenu(engine_context, target, menu, options);
    return menu;
}

/// Makes a menu or a dropdown's list about `rows` rows tall, whatever is in it: what doesn't fit scrolls, with the mouse
/// wheel over it or the scrollbar down its right side (which it leaves room for), cut off at its edges by its own
/// background. For a list too long to show whole
pub fn ScrollingMenu(engine_context: *EngineContext, menu: Entity, rows: usize) !void {
    const half = PADDING / 2;
    menu.GetComponent(LayoutItemComponent).?.mHeight = .{ .Fixed = @as(f32, @floatFromInt(rows)) * MENU_ROW_HEIGHT + 2 * half };
    menu.GetComponent(LayoutComponent).?.mPadding.Right = half + ScrollSystem.THUMB_THICKNESS;
    if (!menu.HasComponent(EntityComponents.MaskComponent)) _ = try menu.AddComponent(engine_context, EntityComponents.MaskComponent{});
    _ = try UIManager.ElementOf(menu).?.AddComponent(engine_context, UIComponents.ScrollComponent{ .mScroll = .Vertical });
    try menu.MarkLayoutDirty(engine_context);
}

/// Takes `entity` and everything in it away: hidden now (its layout item folded) and deleted at the end of the frame,
/// along with the popups the things in it open, which live at the top of the scene rather than inside them (a
/// dropdown's list, a right-click menu, and theirs in turn). A popup in `keep` stays: a menu shared with things that
/// aren't going (ShareContextMenu)
pub fn Remove(engine_context: *EngineContext, entity: Entity, keep: []const Entity) !void {
    if (!entity.IsActive()) return;
    var popups: std.ArrayList(Entity) = .empty;
    try PopupsIn(engine_context.FrameAllocator(), entity, keep, &popups);
    if (entity.GetComponent(LayoutItemComponent)) |item| item.mCollapsed = true;
    try entity.MarkLayoutDirty(engine_context);
    try entity.Delete(engine_context);
    for (popups.items) |popup| {
        if (popup.GetComponent(LayoutItemComponent)) |item| item.mCollapsed = true;
        try popup.Delete(engine_context);
    }
}

/// The popups `entity` and everything in it open, and the ones those open, each once
fn PopupsIn(frame_allocator: std.mem.Allocator, entity: Entity, keep: []const Entity, popups: *std.ArrayList(Entity)) !void {
    if (UIManager.GetUIComponent(entity, PopupRefComponent)) |popup_ref| {
        const popup = popup_ref.mPopup;
        const listed = for (keep) |kept| {
            if (kept.mID == popup.mID and kept.mManager == popup.mManager) break true;
        } else for (popups.items) |found| {
            if (found.mID == popup.mID and found.mManager == popup.mManager) break true;
        } else false;
        if (!listed and popup.IsActive()) {
            try popups.append(frame_allocator, popup);
            try PopupsIn(frame_allocator, popup, keep, popups);
        }
    }
    var children = entity.GetIterator(.Child);
    while (children.next()) |child| try PopupsIn(frame_allocator, child, keep, popups);
}

/// A right-click menu that nothing opens yet, at the top of `near`'s scene: ShareContextMenu makes things open it
pub fn NewContextMenu(engine_context: *EngineContext, near: Entity) !Entity {
    return try PopupList(engine_context, SceneOf(.{ .Entity = near }), PopupComponent{});
}

/// Right clicking `target` opens `menu`, a menu ContextMenu made for something else: one menu for many rows, whose
/// items act on whichever row was right clicked
pub fn ShareContextMenu(engine_context: *EngineContext, target: Entity, menu: Entity, options: Options) !void {
    if (!target.HasComponent(UIElementComponent)) _ = try target.AddComponent(engine_context, UIElementComponent{});
    const element = UIManager.ElementOf(target).?;
    if (element.GetComponent(PopupRefComponent)) |popup_ref| {
        popup_ref.mPopup = menu;
    } else {
        _ = try element.AddComponent(engine_context, PopupRefComponent{ .mPopup = menu });
    }
    if (options.StockScripts) try AddStockScript(engine_context, target, .OpenContextMenu);
}

/// Two panes side by side (a Row) or one above the other (a Column), with a divider between them that dragging moves (the
/// stock Divider script). `fixed` keeps `size` along the split and the other pane takes the rest, so a side panel keeps
/// its width as the window grows. Neither pane has a background of its own. The divider has style "Divider". The split
/// fills what it is in
pub fn Split(engine_context: *EngineContext, parent: Parent, direction: Layout.Direction, fixed: FixedPane, size: f32, options: Options) !SplitParts {
    std.debug.assert(direction != .Grid);
    const root = try NewEntity(engine_context, parent);
    _ = try root.AddComponent(engine_context, LayoutComponent{ .mDirection = direction });
    _ = try root.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fill = 1 }, .mHeight = .{ .Fill = 1 } });

    const fixed_size: Layout.Sizing = .{ .Fixed = @max(size, WidgetActions.MIN_PANE_SIZE) };
    const fill: Layout.Sizing = .{ .Fill = 1 };
    const first = try Pane(engine_context, root, direction, if (fixed == .First) fixed_size else fill);

    const divider = try NewEntity(engine_context, .{ .Entity = root });
    try AddQuad(engine_context, divider, .{}, .{});
    const thin: Layout.Sizing = .{ .Fixed = DIVIDER_SIZE };
    _ = try divider.AddComponent(engine_context, if (direction == .Row)
        LayoutItemComponent{ .mWidth = thin, .mHeight = fill }
    else
        LayoutItemComponent{ .mWidth = fill, .mHeight = thin });
    try UIManager.Style(engine_context, divider, "Divider");
    if (options.StockScripts) try AddStockScript(engine_context, divider, .Divider);

    const second = try Pane(engine_context, root, direction, if (fixed == .Second) fixed_size else fill);
    return .{ .Root = root, .First = first, .Divider = divider, .Second = second };
}

/// A bar of tabs above the pages they show, one at a time. Add the tabs with AddTab. Fills what it is in. The bar has
/// style "TabBar"
pub fn Tabs(engine_context: *EngineContext, parent: Parent) !Entity {
    const tabs = try NewEntity(engine_context, parent);
    _ = try tabs.AddComponent(engine_context, LayoutComponent{ .mDirection = .Column });
    _ = try tabs.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fill = 1 }, .mHeight = .{ .Fill = 1 } });

    const bar = try NewEntity(engine_context, .{ .Entity = tabs });
    try AddQuad(engine_context, bar, .{}, .{});
    _ = try bar.AddComponent(engine_context, LayoutComponent{ .mDirection = .Row, .mGap = PADDING / 2, .mPadding = .{ .Left = PADDING / 2, .Right = PADDING / 2, .Top = PADDING / 2, .Bottom = 0 } });
    _ = try bar.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fill = 1 } });
    try UIManager.Style(engine_context, bar, "TabBar");

    const pages = try NewEntity(engine_context, .{ .Entity = tabs });
    _ = try pages.AddComponent(engine_context, LayoutComponent{ .mDirection = .Column });
    _ = try pages.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fill = 1 }, .mHeight = .{ .Fill = 1 } });
    return tabs;
}

/// A tab at the end of a tab bar (made by Tabs), and the page it shows, which is returned to put what it shows in.
/// Clicking the tab shows its page and hides the others (the stock Tab script); the first tab added starts out shown.
/// The tab has style "Tab". Its page fills the space under the bar
pub fn AddTab(engine_context: *EngineContext, tabs: Entity, title: []const u8, options: Options) !Entity {
    var parts = tabs.GetIterator(.Child);
    const bar = parts.next().?;
    const pages = parts.next().?;
    var existing = bar.GetIterator(.Child);
    const first = existing.next() == null;

    const tab = try NewEntity(engine_context, .{ .Entity = bar });
    try AddQuad(engine_context, tab, .{}, .{});
    _ = try tab.AddComponent(engine_context, LayoutComponent{ .mDirection = .Row, .mPadding = .{ .Left = PADDING, .Right = PADDING, .Top = PADDING / 2, .Bottom = PADDING / 2 } });
    _ = try tab.AddComponent(engine_context, LayoutItemComponent{});
    try UIManager.Style(engine_context, tab, "Tab");
    _ = try Label(engine_context, .{ .Entity = tab }, title);
    if (options.StockScripts) try AddStockScript(engine_context, tab, .Tab);
    if (first) _ = try tab.AddComponent(engine_context, EntityComponents.SelectedTag{});

    const page = try NewEntity(engine_context, .{ .Entity = pages });
    _ = try page.AddComponent(engine_context, LayoutComponent{ .mDirection = .Column });
    _ = try page.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fill = 1 }, .mHeight = .{ .Fill = 1 }, .mCollapsed = !first });
    return page;
}

/// A window at the top of `scene` that floats over the rest of it: a title bar (style "Title") that dragging moves it
/// by (the stock WindowTitle script) with a close button that hides it (the stock CloseWindow script), and under it the
/// window's content, which scrolls when it runs past the bottom. Pressing anywhere on it brings it in front of the scene's other floating windows (the stock Window
/// script), and it starts in front of them. `size` is the whole window's, `at` where its center is from the scene's
/// center. Style "Window"
pub fn FloatingWindow(engine_context: *EngineContext, scene: Scene, title: []const u8, size: Vec2(f32), at: Vec2(f32), options: Options) !WindowParts {
    const window = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    try AddQuad(engine_context, window, .{}, .{});
    _ = try window.AddComponent(engine_context, LayoutComponent{ .mDirection = .Column });
    _ = try window.AddComponent(engine_context, LayoutItemComponent{
        .mWidth = .{ .Fixed = size.x },
        .mHeight = .{ .Fixed = size.y },
        .mPlacement = .{ .Anchored = .{ .Offset = at } },
    });
    try UIManager.Style(engine_context, window, "Window");
    _ = try UIManager.ElementOf(window).?.AddComponent(engine_context, FloatingWindowComponent{});
    if (options.StockScripts) try AddStockScript(engine_context, window, .Window);

    const title_bar = try NewEntity(engine_context, .{ .Entity = window });
    try AddQuad(engine_context, title_bar, .{}, .{});
    _ = try title_bar.AddComponent(engine_context, LayoutComponent{ .mDirection = .Row, .mPadding = .{ .Left = PADDING, .Right = 2, .Top = 2, .Bottom = 2 }, .mCrossAlign = .Center });
    _ = try title_bar.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fill = 1 }, .mHeight = .{ .Fixed = TITLE_SIZE } });
    try UIManager.Style(engine_context, title_bar, "Title");
    if (options.StockScripts) try AddStockScript(engine_context, title_bar, .WindowTitle);
    const shown_title = try Label(engine_context, .{ .Entity = title_bar }, title);
    shown_title.GetComponent(LayoutItemComponent).?.mWidth = .{ .Fill = 1 };
    const close = try ButtonFrame(engine_context, .{ .Entity = title_bar });
    close.GetComponent(LayoutComponent).?.mPadding = .{ .Left = PADDING / 2, .Right = PADDING / 2, .Top = 0, .Bottom = 0 };
    _ = try Label(engine_context, .{ .Entity = close }, "x");
    if (options.StockScripts) try AddStockScript(engine_context, close, .CloseWindow);

    const content = try ScrollArea(engine_context, .{ .Entity = window });

    try WidgetActions.RaiseWindow(engine_context, window);
    return .{ .Window = window, .TitleBar = title_bar, .Content = content };
}

/// Multiplies every size in the widget `root` and everything under it by `factor`: where each sits, gaps and padding,
/// fixed sizes, quads and their corners and borders, and text. For a widget built in overlay units going into a game
/// scene, with StyleSystem.ThemeUnit as the factor, so its numbers are world units at a scale of 1
pub fn ScaleSizes(engine_context: *EngineContext, root: Entity, factor: f32) !void {
    if (root.GetComponent(EntityComponents.TransformComponent)) |transform| {
        try root.SetTranslation(engine_context, transform.GetTranslation().MulScalar(factor));
    }
    if (root.GetComponent(LayoutComponent)) |layout| {
        layout.mGap *= factor;
        layout.mPadding = .{
            .Left = layout.mPadding.Left * factor,
            .Right = layout.mPadding.Right * factor,
            .Top = layout.mPadding.Top * factor,
            .Bottom = layout.mPadding.Bottom * factor,
        };
    }
    if (root.GetComponent(LayoutItemComponent)) |item| {
        for ([_]*Layout.Sizing{ &item.mWidth, &item.mHeight }) |sizing| {
            if (sizing.* == .Fixed) sizing.* = .{ .Fixed = sizing.Fixed * factor };
        }
        if (item.mPlacement == .Anchored) item.mPlacement.Anchored.Offset = item.mPlacement.Anchored.Offset.MulScalar(factor);
    }
    if (root.GetComponent(ShapeComponent)) |shape| {
        if (shape.GetQuad()) |quad| {
            quad.Size = quad.Size.MulScalar(factor);
            quad.CornerRadii = quad.CornerRadii.MulScalar(factor);
        }
    }
    if (root.GetComponent(SurfaceComponent)) |surface| surface.mBorderWidth *= factor;
    if (root.GetComponent(TextComponent)) |text| {
        text.mFontSize *= factor;
        text.mBounds = text.mBounds.MulScalar(factor);
    }
    var children = root.GetIterator(.Child);
    while (children.next()) |child| try ScaleSizes(engine_context, child, factor);
    try root.MarkLayoutDirty(engine_context);
}

/// Puts one of the stock scripts on `entity`
pub fn AddStockScript(engine_context: *EngineContext, entity: Entity, script: StockScript) !void {
    const handle = try engine_context.mAssetManager.GetAssetHandle(engine_context, .{ .File = .{ .rel_path = script.Path(), .path_type = .Eng } });
    //AddScript keeps the reference the handle came with
    try entity.AddScript(engine_context, handle);
}

/// A popup list at the top of `scene` (a popup is never inside what opens it), a little in front of the rest of it, and
/// closed until something opens it: a dropdown's list, a menu. Style "Popup"
fn PopupList(engine_context: *EngineContext, scene: Scene, placement: PopupComponent) !Entity {
    const list = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    try AddQuad(engine_context, list, .{}, .{});
    _ = try list.AddComponent(engine_context, LayoutComponent{ .mDirection = .Column, .mPadding = .All(PADDING / 2) });
    _ = try list.AddComponent(engine_context, LayoutItemComponent{ .mCollapsed = true });
    try UIManager.Style(engine_context, list, "Popup");
    _ = try UIManager.ElementOf(list).?.AddComponent(engine_context, placement);
    try list.SetTranslation(engine_context, Vec3(f32){ .x = 0, .y = 0, .z = POPUP_DEPTH });
    return list;
}

/// A row of a menu as wide as the menu: its text, and room after it for what goes at the right. Style "Header"
fn MenuRow(engine_context: *EngineContext, menu: Entity, text: []const u8) !Entity {
    const row = try NewEntity(engine_context, .{ .Entity = menu });
    try AddQuad(engine_context, row, .{}, .{});
    _ = try row.AddComponent(engine_context, LayoutComponent{
        .mDirection = .Row,
        .mGap = PADDING * 2,
        .mPadding = .{ .Left = PADDING, .Right = PADDING, .Top = PADDING / 2, .Bottom = PADDING / 2 },
        .mCrossAlign = .Center,
    });
    _ = try row.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fill = 1 } });
    try UIManager.Style(engine_context, row, "Header");
    const label = try Label(engine_context, .{ .Entity = row }, text);
    //pushes what comes after it to the right
    label.GetComponent(LayoutItemComponent).?.mWidth = .{ .Fill = 1 };
    return row;
}

/// A folding header row: an arrow box showing whether it is `open` (null for none, only a gap where it would be) and a
/// label. Style "Header", the arrow box "Arrow"
fn FoldHeader(engine_context: *EngineContext, parent: Parent, text: []const u8, open: ?bool) !Entity {
    const header = try NewEntity(engine_context, parent);
    try AddQuad(engine_context, header, .{}, .{});
    _ = try header.AddComponent(engine_context, LayoutComponent{
        .mDirection = .Row,
        .mGap = PADDING / 2,
        .mPadding = .{ .Left = PADDING / 2, .Right = PADDING, .Top = PADDING / 4, .Bottom = PADDING / 4 },
        .mCrossAlign = .Center,
    });
    _ = try header.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fill = 1 } });
    try UIManager.Style(engine_context, header, "Header");

    const arrow = try NewEntity(engine_context, .{ .Entity = header });
    _ = try arrow.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fixed = ARROW_SIZE }, .mHeight = .{ .Fixed = ARROW_SIZE } });
    if (open) |is_open| {
        try AddQuad(engine_context, arrow, .{}, .{});
        _ = try arrow.AddComponent(engine_context, LayoutComponent{ .mDirection = .Row, .mMainAlign = .Center, .mCrossAlign = .Center });
        try UIManager.Style(engine_context, arrow, "Arrow");
        _ = try Label(engine_context, .{ .Entity = arrow }, if (is_open) WidgetActions.ARROW_OPEN else WidgetActions.ARROW_FOLDED);
    }
    _ = try Label(engine_context, .{ .Entity = header }, text);
    return header;
}

/// What a folding header folds: a column, indented by `indent`, shown if `open`
fn FoldContent(engine_context: *EngineContext, parent: Parent, open: bool, indent: f32) !Entity {
    const content = try NewEntity(engine_context, parent);
    _ = try content.AddComponent(engine_context, LayoutComponent{ .mDirection = .Column, .mPadding = .{ .Left = indent, .Right = 0, .Top = 0, .Bottom = 0 } });
    _ = try content.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fill = 1 }, .mCollapsed = !open });
    return content;
}

fn FirstChild(entity: Entity) ?Entity {
    var children = entity.GetIterator(.Child);
    return children.next();
}

/// The scene `parent` is in
fn SceneOf(parent: Parent) Scene {
    return switch (parent) {
        .Entity => |entity| entity.GetComponent(EntitySceneComponent).?.mScene,
        .Scene => |scene| scene,
    };
}

/// One pane of a split: `along` the split's direction, filling it across. No background
fn Pane(engine_context: *EngineContext, split: Entity, direction: Layout.Direction, along: Layout.Sizing) !Entity {
    const pane = try NewEntity(engine_context, .{ .Entity = split });
    _ = try pane.AddComponent(engine_context, LayoutComponent{ .mDirection = .Column });
    const across: Layout.Sizing = .{ .Fill = 1 };
    _ = try pane.AddComponent(engine_context, if (direction == .Row)
        LayoutItemComponent{ .mWidth = along, .mHeight = across }
    else
        LayoutItemComponent{ .mWidth = across, .mHeight = along });
    return pane;
}

/// The container Button and ImageButton put their content in
fn ButtonFrame(engine_context: *EngineContext, parent: Parent) !Entity {
    const button = try NewEntity(engine_context, parent);
    try AddQuad(engine_context, button, .{}, .{});
    _ = try button.AddComponent(engine_context, LayoutComponent{ .mDirection = .Row, .mPadding = .All(PADDING), .mMainAlign = .Center, .mCrossAlign = .Center });
    _ = try button.AddComponent(engine_context, LayoutItemComponent{});
    try UIManager.Style(engine_context, button, "Button");
    return button;
}

/// A new entity under `parent`: inside an entity, DEPTH_STEP in front of it
fn NewEntity(engine_context: *EngineContext, parent: Parent) !Entity {
    switch (parent) {
        .Entity => |entity| {
            const child = try entity.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
            try child.SetTranslation(engine_context, Vec3(f32){ .x = 0, .y = 0, .z = DEPTH_STEP });
            return child;
        },
        .Scene => |scene| return try scene.CreateEntity(engine_context, Entity.DefaultConfig),
    }
}
