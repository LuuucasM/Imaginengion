//! Themes and styles: reading a theme, which state's colors an entity takes from its tags, and what a style writes into
//! an entity's quad and text. Themes are read from text here rather than loaded as assets, except the engine's default,
//! which is read from its file so a broken one is caught. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const ThemeAsset = @import("../../ECSComponents/Asset/ThemeAsset.zig");
const StyleSystem = @import("../../UI/StyleSystem.zig");
const UIManager = @import("../../UI/UIManager.zig");
const Vec4 = @import("../../Math/MathTypes.zig").Vec4;

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const ShapeComponent = EntityComponents.ShapeComponent;
const SurfaceComponent = EntityComponents.SurfaceComponent;
const TextComponent = EntityComponents.TextComponent;
const HoveredTag = EntityComponents.HoveredTag;
const PressedTag = EntityComponents.PressedTag;
const FocusedTag = EntityComponents.FocusedTag;
const SelectedTag = EntityComponents.SelectedTag;
const LayoutDirtyTag = EntityComponents.LayoutDirtyTag;
const StyleComponent = @import("../../ECSComponents/UIComponents.zig").StyleComponent;
const StyleDirtyTag = @import("../../ECSComponents/UIComponents.zig").StyleDirtyTag;

const THEME =
    \\{ "Styles": {
    \\    "Button": {
    \\      "Background": { "Normal": [0.1, 0.2, 0.3, 1], "Hovered": [0.4, 0.5, 0.6, 1], "Pressed": [0.7, 0.8, 0.9, 1], "Selected": [0, 1, 0, 1], "Disabled": [0.2, 0.2, 0.2, 1] },
    \\      "Border": { "Normal": [1, 1, 1, 0.5] },
    \\      "Text": { "Normal": [1, 1, 1, 1] },
    \\      "BorderWidth": 2,
    \\      "CornerRadius": 4,
    \\      "FontSize": 18
    \\    },
    \\    "Plain": { "Background": { "Normal": [0.5, 0.5, 0.5, 1] } }
    \\} }
;

const TestWorld = struct {
    mEngineContext: *EngineContext,
    mTheme: ThemeAsset = .{},
    mScene: Scene = undefined,

    fn Init() !*TestWorld {
        const self = try std.heap.page_allocator.create(TestWorld);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        try engine_context.mUIManager.Init(engine_context.EngineAllocator());
        try engine_context.mEditorWorld.Init(engine_context.EngineAllocator());
        self.mScene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
        try self.mTheme.FromJson(engine_context, THEME);
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        self.mTheme.Deinit(engine_context);
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    /// An entity with a quad shape or a text, and the surface it is painted with, styled `style`
    fn Styled(self: *TestWorld, style: []const u8, what: enum { Shape, Text }) !Entity {
        const engine_context = self.mEngineContext;
        const entity = try self.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
        switch (what) {
            .Shape => _ = try entity.AddComponent(engine_context, ShapeComponent{}),
            .Text => _ = try entity.AddComponent(engine_context, TextComponent{}),
        }
        _ = try entity.AddComponent(engine_context, SurfaceComponent{});
        try UIManager.Style(engine_context, entity, style);
        return entity;
    }

    fn Update(self: *TestWorld) !void {
        //no plain texture to fill with: there are no assets here
        try self.mEngineContext.mUIManager.mStyleSystem.Update(self.mEngineContext, &self.mTheme, .uninit, false);
    }

    /// The style pass for a theme that is new or was just read again
    fn UpdateAll(self: *TestWorld) !void {
        try self.mEngineContext.mUIManager.mStyleSystem.Update(self.mEngineContext, &self.mTheme, .uninit, true);
    }
};

fn ExpectColor(expected: [4]f32, actual: Vec4(f32)) !void {
    try std.testing.expectApproxEqAbs(expected[0], actual.x, 0.0001);
    try std.testing.expectApproxEqAbs(expected[1], actual.y, 0.0001);
    try std.testing.expectApproxEqAbs(expected[2], actual.z, 0.0001);
    try std.testing.expectApproxEqAbs(expected[3], actual.w, 0.0001);
}

test "a theme reads its styles, leaving out what each one leaves out" {
    const world = try TestWorld.Init();
    defer world.Deinit();

    const button = world.mTheme.GetStyle("Button").?;
    try ExpectColor(.{ 0.4, 0.5, 0.6, 1 }, button.Background.Hovered.?);
    try std.testing.expect(button.Background.Focused == null);
    try std.testing.expectEqual(@as(f32, 4), button.CornerRadius.?);
    try std.testing.expect(!button.Font.IsIDValid());

    const plain = world.mTheme.GetStyle("Plain").?;
    try std.testing.expect(plain.Text.Normal == null);
    try std.testing.expect(plain.BorderWidth == null);
    try std.testing.expect(world.mTheme.GetStyle("Missing") == null);
}

test "an entity's colors follow its state, highest first, and a state with no color takes the normal one" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const entity = try world.Styled("Button", .Shape);
    const quad = entity.GetComponent(SurfaceComponent).?;
    try world.Update();
    try ExpectColor(.{ 0.1, 0.2, 0.3, 1 }, quad.mTexOptions.mColor);

    _ = try entity.AddComponent(engine_context, SelectedTag{});
    try world.Update();
    try ExpectColor(.{ 0, 1, 0, 1 }, quad.mTexOptions.mColor);

    //focused outranks selected, and the style has no focused color: the normal one
    _ = try entity.AddComponent(engine_context, FocusedTag{});
    try world.Update();
    try ExpectColor(.{ 0.1, 0.2, 0.3, 1 }, quad.mTexOptions.mColor);

    _ = try entity.AddComponent(engine_context, HoveredTag{});
    try world.Update();
    try ExpectColor(.{ 0.4, 0.5, 0.6, 1 }, quad.mTexOptions.mColor);

    _ = try entity.AddComponent(engine_context, PressedTag{});
    try world.Update();
    try ExpectColor(.{ 0.7, 0.8, 0.9, 1 }, quad.mTexOptions.mColor);

    //disabled outranks them all
    _ = try entity.AddComponent(engine_context, EntityComponents.DisabledTag{});
    try world.Update();
    try ExpectColor(.{ 0.2, 0.2, 0.2, 1 }, quad.mTexOptions.mColor);
}

test "everything inside a disabled entity shows its disabled colors too" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const item = try world.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
    const label = try item.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    _ = try label.AddComponent(engine_context, ShapeComponent{});
    _ = try label.AddComponent(engine_context, SurfaceComponent{});
    try UIManager.Style(engine_context, label, "Button");
    _ = try item.AddComponent(engine_context, EntityComponents.DisabledTag{});
    try world.Update();
    try std.testing.expectEqual(StyleSystem.State.Disabled, StyleSystem.StateOf(label));
    try ExpectColor(.{ 0.2, 0.2, 0.2, 1 }, label.GetComponent(SurfaceComponent).?.mTexOptions.mColor);
}

test "a style writes the border, corners and text it has, and leaves the rest as the entity has it" {
    const world = try TestWorld.Init();
    defer world.Deinit();

    const button = try world.Styled("Button", .Shape);
    const button_text = try world.Styled("Button", .Text);
    const plain = try world.Styled("Plain", .Shape);
    const plain_text = try world.Styled("Plain", .Text);
    plain.GetComponent(SurfaceComponent).?.mBorderWidth = 7;
    plain_text.GetComponent(SurfaceComponent).?.mTexOptions.mColor = .{ .x = 0.25, .y = 0.25, .z = 0.25, .w = 1 };
    try world.Update();

    //a shape's surface takes the background and border, its shape the corners
    const surface = button.GetComponent(SurfaceComponent).?;
    try ExpectColor(.{ 0.1, 0.2, 0.3, 1 }, surface.mTexOptions.mColor);
    try ExpectColor(.{ 1, 1, 1, 0.5 }, surface.mBorderColor);
    try std.testing.expectEqual(@as(f32, 2), surface.mBorderWidth);
    try std.testing.expectEqual(@as(f32, 4), button.GetComponent(ShapeComponent).?.GetQuad().?.CornerRadii.w);
    //a text's surface takes the text color
    try ExpectColor(.{ 1, 1, 1, 1 }, button_text.GetComponent(SurfaceComponent).?.mTexOptions.mColor);

    //plain only has a background
    try ExpectColor(.{ 0.5, 0.5, 0.5, 1 }, plain.GetComponent(SurfaceComponent).?.mTexOptions.mColor);
    try std.testing.expectEqual(@as(f32, 7), plain.GetComponent(SurfaceComponent).?.mBorderWidth);
    try ExpectColor(.{ 0.25, 0.25, 0.25, 1 }, plain_text.GetComponent(SurfaceComponent).?.mTexOptions.mColor);
}

test "a new font size has layout fit the text again, a new color doesn't" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const button = try world.Styled("Button", .Text);
    try button.ClearLayoutDirty(engine_context);
    try world.Update();
    try std.testing.expectEqual(@as(f32, 18), button.GetComponent(TextComponent).?.mFontSize);
    try std.testing.expect(button.HasComponent(LayoutDirtyTag));

    //the same size again: nothing to lay out, even though the colors are written again
    try button.ClearLayoutDirty(engine_context);
    _ = try button.AddComponent(engine_context, HoveredTag{});
    try world.Update();
    try std.testing.expect(!button.HasComponent(LayoutDirtyTag));
}

test "an element whose style the theme hasn't is left alone" {
    const world = try TestWorld.Init();
    defer world.Deinit();

    const entity = try world.Styled("Missing", .Shape);
    entity.GetComponent(SurfaceComponent).?.mTexOptions.mColor = .{ .x = 0.3, .y = 0.3, .z = 0.3, .w = 1 };
    try world.Update();
    try world.Update();
    try ExpectColor(.{ 0.3, 0.3, 0.3, 1 }, entity.GetComponent(SurfaceComponent).?.mTexOptions.mColor);
}

test "styling an entity gives it a UI element, and styling it again changes its style" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const entity = try world.Styled("Plain", .Shape);
    try std.testing.expectEqualStrings("Plain", UIManager.GetUIComponent(entity, StyleComponent).?.mStyle.items);
    try UIManager.Style(engine_context, entity, "Button");
    try std.testing.expectEqualStrings("Button", UIManager.GetUIComponent(entity, StyleComponent).?.mStyle.items);
}

fn IsStyleDirty(entity: Entity) bool {
    return UIManager.HasUIComponent(entity, StyleDirtyTag);
}

test "a styled entity is only styled again when something its style reads changes" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const entity = try world.Styled("Button", .Shape);
    const surface = entity.GetComponent(SurfaceComponent).?;
    try std.testing.expect(IsStyleDirty(entity));
    try world.Update();
    try std.testing.expect(!IsStyleDirty(entity));

    //a color put there by something else stays while nothing changes
    surface.mTexOptions.mColor = .{ .x = 0.3, .y = 0.3, .z = 0.3, .w = 1 };
    try world.Update();
    try ExpectColor(.{ 0.3, 0.3, 0.3, 1 }, surface.mTexOptions.mColor);

    //the pointer moving onto it does
    _ = try entity.AddComponent(engine_context, HoveredTag{});
    try std.testing.expect(IsStyleDirty(entity));
    try world.Update();
    try ExpectColor(.{ 0.4, 0.5, 0.6, 1 }, surface.mTexOptions.mColor);

    //and moving off it
    try entity.RemoveComponentSync(engine_context, HoveredTag);
    try world.Update();
    try ExpectColor(.{ 0.1, 0.2, 0.3, 1 }, surface.mTexOptions.mColor);
}

test "a style taken once is taken off after, and what is set on the entity then stays" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const entity = try world.Styled("Button", .Shape);
    UIManager.StyleOnce(entity);
    try world.Update();
    const surface = entity.GetComponent(SurfaceComponent).?;
    try ExpectColor(.{ 0.1, 0.2, 0.3, 1 }, surface.mTexOptions.mColor);
    try std.testing.expect(UIManager.GetUIComponent(entity, StyleComponent) == null);

    //a color set by hand stays, even through what would restyle it
    surface.mTexOptions.mColor = .{ .x = 0.3, .y = 0.3, .z = 0.3, .w = 1 };
    _ = try entity.AddComponent(engine_context, HoveredTag{});
    try world.UpdateAll();
    try ExpectColor(.{ 0.3, 0.3, 0.3, 1 }, entity.GetComponent(SurfaceComponent).?.mTexOptions.mColor);
}

test "a state tag removed the usual way is gone in time for the next style pass" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const entity = try world.Styled("Button", .Shape);
    _ = try entity.AddComponent(engine_context, SelectedTag{});
    try world.Update();
    try ExpectColor(.{ 0, 1, 0, 1 }, entity.GetComponent(SurfaceComponent).?.mTexOptions.mColor);

    //not left until the end of the frame, after the pass that would have seen it still there
    try entity.RemoveComponent(engine_context, SelectedTag);
    try std.testing.expect(!entity.HasComponent(SelectedTag));
    try world.Update();
    try ExpectColor(.{ 0.1, 0.2, 0.3, 1 }, entity.GetComponent(SurfaceComponent).?.mTexOptions.mColor);
}

test "disabling an entity styles everything inside it again" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const item = try world.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
    const label = try item.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    _ = try label.AddComponent(engine_context, ShapeComponent{});
    _ = try label.AddComponent(engine_context, SurfaceComponent{});
    try UIManager.Style(engine_context, label, "Button");
    try world.Update();
    try ExpectColor(.{ 0.1, 0.2, 0.3, 1 }, label.GetComponent(SurfaceComponent).?.mTexOptions.mColor);

    _ = try item.AddComponent(engine_context, EntityComponents.DisabledTag{});
    try std.testing.expect(IsStyleDirty(label));
    try world.Update();
    try ExpectColor(.{ 0.2, 0.2, 0.2, 1 }, label.GetComponent(SurfaceComponent).?.mTexOptions.mColor);

    try item.RemoveComponentSync(engine_context, EntityComponents.DisabledTag);
    try world.Update();
    try ExpectColor(.{ 0.1, 0.2, 0.3, 1 }, label.GetComponent(SurfaceComponent).?.mTexOptions.mColor);
}

test "a new style, or a new theme, styles again" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const entity = try world.Styled("Button", .Shape);
    const surface = entity.GetComponent(SurfaceComponent).?;
    try world.Update();

    try UIManager.Style(engine_context, entity, "Plain");
    try world.Update();
    try ExpectColor(.{ 0.5, 0.5, 0.5, 1 }, surface.mTexOptions.mColor);

    //a theme read again restyles even what wasn't marked
    surface.mTexOptions.mColor = .{ .x = 0.3, .y = 0.3, .z = 0.3, .w = 1 };
    try world.UpdateAll();
    try ExpectColor(.{ 0.5, 0.5, 0.5, 1 }, surface.mTexOptions.mColor);
}

test "a part added to a styled entity later is styled too" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const entity = try world.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try entity.AddComponent(engine_context, ShapeComponent{});
    try UIManager.Style(engine_context, entity, "Button");
    try world.Update();

    _ = try entity.AddComponent(engine_context, SurfaceComponent{});
    try world.Update();
    try ExpectColor(.{ 0.1, 0.2, 0.3, 1 }, entity.GetComponent(SurfaceComponent).?.mTexOptions.mColor);
}

test "the engine's default theme reads, with every style the editor's look needs" {
    const engine_context = try std.heap.page_allocator.create(EngineContext);
    defer std.heap.page_allocator.destroy(engine_context);
    engine_context.* = .{};
    const engine_allocator = engine_context.EngineAllocator();
    //file reads go through the context's Io, which forwards to this
    engine_context._Internal.ThreadedIO = std.Io.Threaded.init(engine_context._Internal.EngineGPA.allocator(), .{
        .concurrent_limit = .nothing,
        .async_limit = .nothing,
    });
    //no Setup: its default assets need the GPU. The theme's fonts are only looked up, not loaded
    try engine_context.mAssetManager.Init(engine_context);

    const contents = try std.Io.Dir.cwd().readFileAlloc(engine_context.Io(), UIManager.DEFAULT_THEME_PATH, engine_context.FrameAllocator(), .unlimited);
    var theme: ThemeAsset = .{};
    try theme.FromJson(engine_context, contents);
    for ([_][]const u8{ "Window", "Header", "Button", "Field", "Tab", "Title", "Popup", "Text", "Caret", "Scrollbar", "AxisX", "AxisY", "AxisZ", "AxisW", "Checkbox", "Separator", "Swatch", "TextDim", "MenuBar", "MenuCheck", "Arrow" }) |name| {
        if (theme.GetStyle(name) == null) {
            std.debug.print("the default theme has no style '{s}'\n", .{name});
            return error.TestMissingStyle;
        }
    }
    try std.testing.expect(theme.GetStyle("AxisX").?.Font.IsIDValid());
    //every label's style names a font: text with none takes up no room and draws nothing
    try std.testing.expect(theme.GetStyle("Text").?.Font.IsIDValid());
    try std.testing.expect(theme.GetStyle("TextDim").?.Font.IsIDValid());
    theme.Deinit(engine_context);

    //the asset manager, minus the default assets Init never set up and the working directory handle it does not own
    const asset_manager = &engine_context.mAssetManager;
    asset_manager.mECSManager.Deinit(engine_context);
    asset_manager.mUUIDToWorldID.deinit(engine_allocator);
    asset_manager.mEventManager.Deinit(engine_allocator);
    asset_manager.mCWDPath.deinit(engine_allocator);
    _ = engine_context._Internal.EngineGPA.deinit();
}

test "a style names a theme file of its own, and is taken out of it instead of the editor's theme" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    const engine_context = try std.heap.page_allocator.create(EngineContext);
    defer std.heap.page_allocator.destroy(engine_context);
    engine_context.* = .{};
    const engine_allocator = engine_context.EngineAllocator();
    engine_context._Internal.ThreadedIO = std.Io.Threaded.init(engine_context._Internal.EngineGPA.allocator(), .{
        .concurrent_limit = .nothing,
        .async_limit = .nothing,
    });
    //no Setup: its default assets need the GPU
    try engine_context.mAssetManager.Init(engine_context);
    try engine_context.mUIManager.Init(engine_allocator);
    try engine_context.mEditorWorld.Init(engine_allocator);
    var editor_theme = ThemeAsset{};
    try editor_theme.FromJson(engine_context, THEME);
    defer {
        editor_theme.Deinit(engine_context);
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        const asset_manager = &engine_context.mAssetManager;
        asset_manager.mECSManager.Deinit(engine_context);
        asset_manager.mUUIDToWorldID.deinit(engine_allocator);
        asset_manager.mEventManager.Deinit(engine_allocator);
        asset_manager.mCWDPath.deinit(engine_allocator);
        _ = engine_context._Internal.EngineGPA.deinit();
    }

    //a game's own theme, with its own "Button"
    try tmp_dir.dir.writeFile(engine_context.Io(), .{ .sub_path = "Game.imtheme", .data =
        \\{ "Styles": { "Button": { "Background": { "Normal": [1, 0, 0, 1] } } } }
    });
    const rel_path = try std.fmt.allocPrint(engine_context.FrameAllocator(), ".zig-cache/tmp/{s}/Game.imtheme", .{tmp_dir.sub_path});
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    const entity = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try entity.AddComponent(engine_context, ShapeComponent{});
    _ = try entity.AddComponent(engine_context, SurfaceComponent{});
    try UIManager.Style(engine_context, entity, "Button");
    UIManager.GetUIComponent(entity, StyleComponent).?.mTheme = try engine_context.mAssetManager.GetAssetHandle(engine_context, .{ .File = .{ .rel_path = rel_path, .path_type = .Eng } });

    try engine_context.mUIManager.mStyleSystem.Update(engine_context, &editor_theme, .uninit, false);
    try ExpectColor(.{ 1, 0, 0, 1 }, entity.GetComponent(SurfaceComponent).?.mTexOptions.mColor);
    //read in, and so watched for its file changing
    try std.testing.expect(!engine_context.mUIManager.mStyleSystem.ThemesReread(engine_context));
}
