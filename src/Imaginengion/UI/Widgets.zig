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
const Layout = @import("Layout.zig");
const Vec2 = @import("../Math/MathTypes.zig").Vec2;

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const QuadComponent = EntityComponents.QuadComponent;
const TextComponent = EntityComponents.TextComponent;
const LayoutComponent = EntityComponents.LayoutComponent;
const LayoutItemComponent = EntityComponents.LayoutItemComponent;

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
    const row = try NewEntity(engine_context, parent);
    _ = try row.AddComponent(engine_context, QuadComponent{});
    _ = try row.AddComponent(engine_context, LayoutComponent{
        .mDirection = .Row,
        .mPadding = .{ .Left = PADDING, .Right = PADDING, .Top = PADDING / 2, .Bottom = PADDING / 2 },
        .mCrossAlign = .Center,
    });
    _ = try row.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fill = 1 } });
    try UIManager.Style(engine_context, row, "Header");
    if (options.StockScripts) try AddStockScript(engine_context, row, .Select);

    _ = try Label(engine_context, .{ .Entity = row }, text);
    return row;
}

/// Puts one of the stock scripts on `entity`
pub fn AddStockScript(engine_context: *EngineContext, entity: Entity, script: StockScript) !void {
    const handle = try engine_context.mAssetManager.GetAssetHandle(engine_context, .{ .File = .{ .rel_path = script.Path(), .path_type = .Eng } });
    //AddScript keeps the reference the handle came with
    try entity.AddScript(engine_context, handle);
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
