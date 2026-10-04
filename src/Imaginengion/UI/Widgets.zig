//! Builders for the common widgets: each makes an entity tree out of the primitives (quads, text, layout, styles, and
//! for some a stock script) under a parent, and hands back its root. A widget isn't anything to the engine once it is
//! made: a button is a styled quad with a label, and what it does is whatever script is put on it.
//! Built in code for now, which is easy to test. Once these settle, saving one as a template file is a single call, and
//! templates can take over.
const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const AssetHandle = @import("../ECSObjects/AssetHandle.zig");
const UIManager = @import("UIManager.zig");
const NumberFieldSystem = @import("NumberFieldSystem.zig");
const WidgetActions = @import("WidgetActions.zig");
const Layout = @import("Layout.zig");
const MathTypes = @import("../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;
const Vec4 = MathTypes.Vec4;

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const QuadComponent = EntityComponents.QuadComponent;
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
/// A checkbox's box
pub const CHECKBOX_SIZE: f32 = 16;
/// How far in front of the rest of its scene a dropdown's list is, so it is drawn over what it hangs over
pub const POPUP_DEPTH: f32 = 1;
/// A color field's swatch
pub const SWATCH_SIZE: f32 = 20;
/// A folding header's arrow box, and the room a leaf tree node leaves where one would be
pub const ARROW_SIZE: f32 = 16;
/// How far a tree node's children sit in from it
pub const INDENT: f32 = 16;
/// A checkable menu item's check box
pub const MENU_CHECK_SIZE: f32 = 10;

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

/// A line of text, sized to fit it. Style "Text"
pub fn Label(engine_context: *EngineContext, parent: Parent, text: []const u8) !Entity {
    const entity = try NewEntity(engine_context, parent);
    var text_component = TextComponent{ .mFontSize = TEXT_SIZE };
    try text_component.SetText(engine_context, text);
    _ = try entity.AddComponent(engine_context, text_component);
    _ = try entity.AddComponent(engine_context, LayoutItemComponent{});
    try UIManager.Style(engine_context, entity, "Text");
    return entity;
}

/// A thin line across whatever it is in. Style "Separator"
pub fn Separator(engine_context: *EngineContext, parent: Parent) !Entity {
    const entity = try NewEntity(engine_context, parent);
    _ = try entity.AddComponent(engine_context, QuadComponent{});
    _ = try entity.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fill = 1 }, .mHeight = .{ .Fixed = 1 } });
    try UIManager.Style(engine_context, entity, "Separator");
    return entity;
}

/// A texture shown at `size`. The image takes its own reference to the texture
pub fn Image(engine_context: *EngineContext, parent: Parent, texture: AssetHandle, size: Vec2(f32)) !Entity {
    const entity = try NewEntity(engine_context, parent);
    texture.RetainAsset();
    _ = try entity.AddComponent(engine_context, QuadComponent{ .mTexture = texture });
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
    _ = try box.AddComponent(engine_context, QuadComponent{});
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
    _ = try row.AddComponent(engine_context, QuadComponent{});
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
    _ = try field.AddComponent(engine_context, QuadComponent{});
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
        _ = try axis.AddComponent(engine_context, QuadComponent{});
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
    _ = try button.AddComponent(engine_context, QuadComponent{});
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
    _ = try swatch.AddComponent(engine_context, QuadComponent{});
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
    _ = try bar.AddComponent(engine_context, QuadComponent{});
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
    _ = try button.AddComponent(engine_context, QuadComponent{});
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
        _ = try check.AddComponent(engine_context, QuadComponent{});
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
    const menu = try PopupList(engine_context, SceneOf(.{ .Entity = target }), PopupComponent{});
    if (!target.HasComponent(UIElementComponent)) _ = try target.AddComponent(engine_context, UIElementComponent{});
    const element = UIManager.ElementOf(target).?;
    if (element.GetComponent(PopupRefComponent)) |popup_ref| {
        popup_ref.mPopup = menu;
    } else {
        _ = try element.AddComponent(engine_context, PopupRefComponent{ .mPopup = menu });
    }
    if (options.StockScripts) try AddStockScript(engine_context, target, .OpenContextMenu);
    return menu;
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
    _ = try list.AddComponent(engine_context, QuadComponent{});
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
    _ = try row.AddComponent(engine_context, QuadComponent{});
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
    _ = try header.AddComponent(engine_context, QuadComponent{});
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
        _ = try arrow.AddComponent(engine_context, QuadComponent{});
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

/// The container Button and ImageButton put their content in
fn ButtonFrame(engine_context: *EngineContext, parent: Parent) !Entity {
    const button = try NewEntity(engine_context, parent);
    _ = try button.AddComponent(engine_context, QuadComponent{});
    _ = try button.AddComponent(engine_context, LayoutComponent{ .mDirection = .Row, .mPadding = .All(PADDING), .mMainAlign = .Center, .mCrossAlign = .Center });
    _ = try button.AddComponent(engine_context, LayoutItemComponent{});
    try UIManager.Style(engine_context, button, "Button");
    return button;
}

fn NewEntity(engine_context: *EngineContext, parent: Parent) !Entity {
    return switch (parent) {
        .Entity => |entity| try entity.CreateChild(engine_context, .Entity, Entity.DefaultConfig),
        .Scene => |scene| try scene.CreateEntity(engine_context, Entity.DefaultConfig),
    };
}
