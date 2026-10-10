//! Reference fields taking dropped hierarchy rows (UI/Inspector.zig EntityRef / SceneRef, UI/BindingSystem.zig): a row
//! of the right kind becomes the field's object and the wrong kind is turned down, an overlay-only field turns down a
//! game layer scene, a field's right-click Clear empties it (an asset field's too), and the Components panel's Possess
//! box possessing a dropped entity through Player.Possess and letting go of it on Clear. Drops and clicks are sent the
//! way the pointer system sends them. No window or renderer needed. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const Player = @import("../../ECSObjects/Player.zig");
const AssetHandle = @import("../../ECSObjects/AssetHandle.zig");
const UIManager = @import("../../UI/UIManager.zig");
const Inspector = @import("../../UI/Inspector.zig");
const WidgetActions = @import("../../UI/WidgetActions.zig");
const ComponentsPanel = @import("../../EditorPanels/ComponentsPanel.zig");

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const TextComponent = EntityComponents.TextComponent;
const LayoutComponent = EntityComponents.LayoutComponent;
const SurfaceComponent = EntityComponents.SurfaceComponent;
const PlayerSlotComponent = EntityComponents.PlayerSlotComponent;
const ObjectRefComponent = EntityComponents.ObjectRefComponent;
const FileRefComponent = EntityComponents.FileRefComponent;
const SpawnPossComponent = @import("../../ECSComponents/SComponents.zig").SpawnPossComponent;
const PlayerComponents = @import("../../ECSComponents/PComponents.zig");
const OverlayComponent = PlayerComponents.OverlayComponent;
const PossessComponent = PlayerComponents.PossessComponent;

const NO_SCRIPTS = @import("../../UI/Widgets.zig").Options{ .StockScripts = false };

const TestWorld = struct {
    mEngineContext: *EngineContext,
    mUIScene: Scene = undefined,
    mLevel: Scene = undefined,

    fn Init() !*TestWorld {
        const self = try std.heap.page_allocator.create(TestWorld);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        engine_context._Internal.ThreadedIO = std.Io.Threaded.init(engine_context._Internal.EngineGPA.allocator(), .{
            .concurrent_limit = .nothing,
            .async_limit = .nothing,
        });
        try engine_context.mAssetManager.Init(engine_context);
        try engine_context.mUIManager.Init(engine_context.EngineAllocator());
        try engine_context.mEditorWorld.Init(engine_context.EngineAllocator());
        try engine_context.mGameWorld.Init(engine_context.EngineAllocator());
        self.mUIScene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
        self.mLevel = try engine_context.mGameWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        const engine_allocator = engine_context.EngineAllocator();
        engine_context.mGameWorld.Deinit(engine_context);
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        const asset_manager = &engine_context.mAssetManager;
        asset_manager.mECSManager.Deinit(engine_context);
        asset_manager.mUUIDToWorldID.deinit(engine_allocator);
        asset_manager.mEventManager.Deinit(engine_allocator);
        asset_manager.mCWDPath.deinit(engine_allocator);
        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    /// The rows of `object`'s component, under a fresh panel
    fn Render(self: *TestWorld, object: anytype, comptime component_type: type) !Entity {
        const panel = try self.mUIScene.CreateEntity(self.mEngineContext, Entity.DefaultConfig);
        try Inspector.RenderComponent(self.mEngineContext, panel, panel, object, component_type, NO_SCRIPTS);
        return panel;
    }

    /// Something being dragged carrying `object`, the way a hierarchy row does
    fn Row(self: *TestWorld, object: anytype) !Entity {
        const row = try self.mUIScene.CreateEntity(self.mEngineContext, Entity.DefaultConfig);
        _ = try row.AddComponent(self.mEngineContext, ObjectRefComponent{ .mObject = .Of(object) });
        return row;
    }

    fn Drop(self: *TestWorld, source: Entity, target: Entity) !void {
        try self.mEngineContext.mUIManager.OnPointerEvent(self.mEngineContext, .{ .mEntity = target, .mEvent = .{ .PointerDropped = .{ .mSource = source, .mPosition = .{ .x = 0, .y = 0, .z = 0 } } } });
    }

    /// A left click on the Clear item of `box`'s right-click menu
    fn Clear(self: *TestWorld, box: Entity) !void {
        var items = WidgetActions.PopupOf(box).?.GetIterator(.Child);
        const clear = items.next().?;
        try self.mEngineContext.mUIManager.OnPointerEvent(self.mEngineContext, .{ .mEntity = clear, .mEvent = .{ .PointerClicked = .{ .mButton = .BUTTON_LEFT, .mClicks = 1, .mPosition = .{ .x = 0, .y = 0, .z = 0 }, .mTarget = clear } } });
    }

    fn ShowFields(self: *TestWorld) !void {
        try self.mEngineContext.mUIManager.mBindingSystem.Update(self.mEngineContext);
    }
};

/// The box of a panel's only row
fn BoxOf(panel: Entity) Entity {
    var rows = panel.GetIterator(.Child);
    var parts = rows.next().?.GetIterator(.Child);
    _ = parts.next().?; //the label
    return parts.next().?;
}

fn TextIn(box: Entity) []const u8 {
    return UIManager.LabelOf(box).?.GetComponent(TextComponent).?.mText.items;
}

test "an entity field takes a dropped entity row, turns down a scene row, and Clear empties it" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    _ = try world.mLevel.AddComponent(engine_context, SpawnPossComponent{});
    const hero = try world.mLevel.CreateEntity(engine_context, Entity.DefaultConfig);
    try hero.SetName(engine_context, "Hero");
    const box = BoxOf(try world.Render(world.mLevel, SpawnPossComponent));
    try std.testing.expectEqualStrings("None", TextIn(box));

    try world.Drop(try world.Row(world.mLevel), box);
    try std.testing.expectEqual(Entity.NullObject, world.mLevel.GetComponent(SpawnPossComponent).?.mEntityRef.mID);

    try world.Drop(try world.Row(hero), box);
    try std.testing.expectEqual(hero.mID, world.mLevel.GetComponent(SpawnPossComponent).?.mEntityRef.mID);
    try world.ShowFields();
    try std.testing.expectEqualStrings("Hero", TextIn(box));

    try world.Clear(box);
    try std.testing.expectEqual(Entity.NullObject, world.mLevel.GetComponent(SpawnPossComponent).?.mEntityRef.mID);
    //the Clear item is never shown a value: it still says Clear
    try world.ShowFields();
    var items = WidgetActions.PopupOf(box).?.GetIterator(.Child);
    try std.testing.expectEqualStrings("Clear", UIManager.LabelOf(items.next().?).?.GetComponent(TextComponent).?.mText.items);
}

test "an overlay field turns down a game layer scene and takes an overlay one" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const player = try engine_context.mGameWorld.CreatePlayer(engine_context, Player.DefaultConfig);
    _ = try player.AddComponent(engine_context, OverlayComponent{});
    const hud = try engine_context.mGameWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    const box = BoxOf(try world.Render(player, OverlayComponent));

    try world.Drop(try world.Row(world.mLevel), box);
    try std.testing.expectEqual(Scene.NullObject, player.GetComponent(OverlayComponent).?.mScene.mID);
    try world.Drop(try world.Row(hud), box);
    try std.testing.expectEqual(hud.mID, player.GetComponent(OverlayComponent).?.mScene.mID);
}

test "an asset field's Clear lets go of its asset" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const entity = try world.mLevel.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try entity.AddComponent(engine_context, SurfaceComponent{});
    const panel = try world.Render(entity, SurfaceComponent);
    //the texture's row: its box is after the label and the thumbnail
    var rows = panel.GetIterator(.Child);
    //the rows are the component's own, with the material's section among them: the one labelled Texture
    const row = while (rows.next()) |candidate| {
        const label = UIManager.LabelOf(candidate) orelse continue;
        if (std.mem.eql(u8, label.GetComponent(TextComponent).?.mText.items, "Texture")) break candidate;
    } else unreachable;
    var parts = row.GetIterator(.Child);
    _ = parts.next().?;
    _ = parts.next().?;
    const box = parts.next().?;

    const picture = try world.mUIScene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try picture.AddComponent(engine_context, try FileRefComponent.Init(engine_context, "src/Imaginengion/EngineAssets/textures/White.png", .Eng));
    try world.Drop(picture, box);
    try std.testing.expect(entity.GetComponent(SurfaceComponent).?.mTexture.mID != AssetHandle.NullObject);
    try world.Clear(box);
    try std.testing.expectEqual(AssetHandle.NullObject, entity.GetComponent(SurfaceComponent).?.mTexture.mID);
}

test "the Components panel's Possess box possesses a dropped entity, linking both sides, and Clear lets go" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const page = try world.mUIScene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try page.AddComponent(engine_context, LayoutComponent{ .mDirection = .Column });
    var panel = try ComponentsPanel.Build(engine_context, page, NO_SCRIPTS);
    defer panel.Deinit(engine_context.EngineAllocator());

    var player_config = Player.DefaultConfig;
    player_config.bAddPossessComponent = true;
    const player = try engine_context.mGameWorld.CreatePlayer(engine_context, player_config);
    const hero = try world.mLevel.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try hero.AddComponent(engine_context, PlayerSlotComponent{});
    try panel.Update(engine_context, .{ .player = player });
    const box = panel.mPossessBox.?;

    panel.OnDrop(box, .{ .mSource = try world.Row(hero), .mPosition = .{ .x = 0, .y = 0, .z = 0 } });
    try std.testing.expectEqual(hero.mID, player.GetComponent(PossessComponent).?.mPossessedEntity.mID);
    try std.testing.expectEqual(player.mID, hero.GetComponent(PlayerSlotComponent).?.mPlayerEntity.mID);
    try panel.Update(engine_context, .{ .player = player });
    try world.ShowFields();
    try std.testing.expect(!std.mem.eql(u8, "None", TextIn(box)));

    var clear: ?Entity = null;
    for (panel.mButtons.items) |entry| {
        if (entry.Action == .Unpossess) clear = entry.Button;
    }
    try panel.Run(engine_context, panel.ActionOf(clear.?).?);
    try std.testing.expectEqual(Entity.NullObject, player.GetComponent(PossessComponent).?.mPossessedEntity.mID);
    try std.testing.expectEqual(Player.NullObject, hero.GetComponent(PlayerSlotComponent).?.mPlayerEntity.mID);
}
