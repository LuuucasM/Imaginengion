//! The rows each component's UIRender asks for (the Components panel's content): every component the panel lists for
//! each of the four object types builds its rows, and the ones that do more than show a field do it: a collider's
//! shape deciding its sizes, a viewpoint's FOV in degrees reprojecting, a layout item's size kinds starting at their
//! defaults, a pin setting anchor and pivot together, and an audio component's bus picked from the bus tree. Edits are
//! made the way the widgets make them. No window or renderer needed. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const Player = @import("../../ECSObjects/Player.zig");
const GameContext = @import("../../ECSObjects/GameContext.zig");
const Bus = @import("../../ECSObjects/Bus.zig");
const UIManager = @import("../../UI/UIManager.zig");
const Inspector = @import("../../UI/Inspector.zig");
const WidgetActions = @import("../../UI/WidgetActions.zig");

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const TextComponent = EntityComponents.TextComponent;
const AttribComponent = EntityComponents.AttribComponent;
const ColliderComponent = EntityComponents.ColliderComponent;
const ViewpointComponent = EntityComponents.ViewpointComponent;
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const AudioComponent = EntityComponents.AudioComponent;
const UIElementComponent = EntityComponents.UIElementComponent;

const NO_SCRIPTS = @import("../../UI/Widgets.zig").Options{ .StockScripts = false };

const TestWorld = struct {
    mEngineContext: *EngineContext,
    mScene: Scene = undefined,
    mPanel: Entity = .uninit,

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
        try engine_context.mAudioManager.InitMixer(engine_context);
        self.mScene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
        self.mPanel = try self.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        const engine_allocator = engine_context.EngineAllocator();
        engine_context.mGameWorld.Deinit(engine_context);
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        engine_context.mAudioManager.DeinitMixer(engine_context);
        const asset_manager = &engine_context.mAssetManager;
        asset_manager.mECSManager.Deinit(engine_context);
        asset_manager.mUUIDToWorldID.deinit(engine_allocator);
        asset_manager.mEventManager.Deinit(engine_allocator);
        asset_manager.mCWDPath.deinit(engine_allocator);
        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    /// The rows of `object`'s component, under a fresh panel each time
    fn Render(self: *TestWorld, object: anytype, comptime component_type: type) !Entity {
        const panel = try self.mScene.CreateEntity(self.mEngineContext, Entity.DefaultConfig);
        try Inspector.RenderComponent(self.mEngineContext, panel, panel, object, component_type, NO_SCRIPTS);
        return panel;
    }

    fn ProcessUIEvents(self: *TestWorld) !void {
        try self.mEngineContext.mUIManager.ProcessUIEvents(self.mEngineContext, .{});
    }
};

/// The rows' labels, the first child of each
fn Labels(panel: Entity, out: [][]const u8) usize {
    var count: usize = 0;
    var rows = panel.GetIterator(.Child);
    while (rows.next()) |row| : (count += 1) {
        if (count >= out.len) continue;
        const label = UIManager.LabelOf(row) orelse {
            out[count] = "";
            continue;
        };
        out[count] = label.GetComponent(TextComponent).?.mText.items;
    }
    return count;
}

fn Part(panel: Entity, row_index: usize, part: usize) Entity {
    var rows = panel.GetIterator(.Child);
    var row = rows.next().?;
    for (0..row_index) |_| row = rows.next().?;
    var parts = row.GetIterator(.Child);
    var entity = parts.next().?;
    for (0..part) |_| entity = parts.next().?;
    return entity;
}

fn Pick(world: *TestWorld, dropdown: Entity, index: usize) !void {
    try WidgetActions.TogglePopup(world.mEngineContext, dropdown);
    var choices = WidgetActions.PopupOf(dropdown).?.GetIterator(.Child);
    var choice = choices.next().?;
    for (0..index) |_| choice = choices.next().?;
    try WidgetActions.Choose(world.mEngineContext, choice);
    try world.ProcessUIEvents();
}

/// Gives `object` every component in `list` it can be given at its defaults, and builds each one's rows
fn RenderAll(world: *TestWorld, object: anytype, comptime list: []const type) !void {
    inline for (list) |component_type| {
        if (!object.HasComponent(component_type)) _ = try object.AddComponent(world.mEngineContext, component_type{});
        _ = try world.Render(object, component_type);
    }
}

test "every component the Components panel lists builds its rows, for all four object types" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const game_scene = try engine_context.mGameWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    //a UI element is made by the UI manager when its component is added, not at a default
    const entity_list = comptime blk: {
        var list: []const type = &.{};
        for (EntityComponents.ComponentPanelList) |component_type| {
            if (component_type != UIElementComponent) list = list ++ &[_]type{component_type};
        }
        break :blk list;
    };
    try RenderAll(world, try game_scene.CreateEntity(engine_context, Entity.DefaultConfig), entity_list);
    try RenderAll(world, game_scene, &@import("../../ECSComponents/SComponents.zig").ComponentsPanelList);
    try RenderAll(world, try engine_context.mGameWorld.CreatePlayer(engine_context, Player.DefaultConfig), &@import("../../ECSComponents/PComponents.zig").ComponentsPanelList);
    try RenderAll(world, try engine_context.mGameWorld.CreateGameContext(engine_context, GameContext.DefaultConfig), &@import("../../ECSComponents/GCComponents.zig").ComponentsPanelList);
}

test "a collider's shape decides its sizes, and a viewpoint's FOV is in degrees and reprojects" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const entity = try world.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try entity.AddComponent(engine_context, ColliderComponent{ .mShape = .Box });

    var labels: [8][]const u8 = undefined;
    _ = Labels(try world.Render(entity, ColliderComponent), &labels);
    try std.testing.expectEqualStrings("Box Size", labels[1]);
    entity.GetComponent(ColliderComponent).?.mShape = .Sphere;
    _ = Labels(try world.Render(entity, ColliderComponent), &labels);
    try std.testing.expectEqualStrings("Radius", labels[1]);

    _ = try entity.AddComponent(engine_context, ViewpointComponent{});
    const panel = try world.Render(entity, ViewpointComponent);
    const fov = Part(panel, 1, 1);
    fov.GetComponent(AttribComponent).?.mData.SetFromFloat(90);
    const projection_before = entity.GetComponent(ViewpointComponent).?.mProjection;
    try engine_context.mUIManager.SendToChain(engine_context, fov, .ValueChanged);
    try world.ProcessUIEvents();
    const viewpoint = entity.GetComponent(ViewpointComponent).?;
    try std.testing.expectApproxEqAbs(std.math.pi / 2.0, viewpoint.mPerspectiveFOVRad, 0.0001);
    try std.testing.expect(!std.meta.eql(projection_before, viewpoint.mProjection));
}

test "a layout item's size kinds start at their defaults, and a pin sets the anchor and the pivot together" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const entity = try world.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try entity.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .Fit });
    var panel = try world.Render(entity, LayoutItemComponent);

    //Fixed picked for the width: it starts at 100
    try Pick(world, Part(panel, 0, 1), 0);
    try std.testing.expectEqual(@as(f32, 100), entity.GetComponent(LayoutItemComponent).?.mWidth.Fixed);

    //anchored, then pinned to the top right
    entity.GetComponent(LayoutItemComponent).?.mPlacement = .{ .Anchored = .{} };
    panel = try world.Render(entity, LayoutItemComponent);
    var labels: [16][]const u8 = undefined;
    const count = Labels(panel, &labels);
    var pin_row: usize = 0;
    for (labels[0..count], 0..) |label, i| {
        if (std.mem.eql(u8, label, "Pin To")) pin_row = i;
    }
    try std.testing.expect(pin_row > 0);
    try std.testing.expectEqualStrings("Center", UIManager.LabelOf(Part(panel, pin_row, 1)).?.GetComponent(TextComponent).?.mText.items);
    try Pick(world, Part(panel, pin_row, 1), 2);
    const anchoring = entity.GetComponent(LayoutItemComponent).?.mPlacement.Anchored;
    try std.testing.expect(anchoring.Anchor.x == 1 and anchoring.Anchor.y == 1 and anchoring.Pivot.x == 1 and anchoring.Pivot.y == 1);
}

test "an audio component's bus is picked from the buses, Master first and each before the ones under it" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const master = engine_context.mAudioManager.GetMasterBus();
    const music = try master.CreateChild(engine_context, .Entity, Bus.DefaultConfig);
    try music.SetName(engine_context, "Music");
    const entity = try world.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try entity.AddComponent(engine_context, AudioComponent{});
    const panel = try world.Render(entity, AudioComponent);

    var labels: [16][]const u8 = undefined;
    const count = Labels(panel, &labels);
    try std.testing.expectEqualStrings("Bus", labels[count - 1]);
    const dropdown = Part(panel, count - 1, 1);
    //no bus picked plays through Master
    try std.testing.expectEqualStrings("Master", UIManager.LabelOf(dropdown).?.GetComponent(TextComponent).?.mText.items);
    try Pick(world, dropdown, 1);
    try std.testing.expectEqual(music.mID, entity.GetComponent(AudioComponent).?.mBus.mID);
}
