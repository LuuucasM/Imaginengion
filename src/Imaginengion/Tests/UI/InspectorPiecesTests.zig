//! The inspector's (UI/Inspector.zig) pieces for the Components panel, on real components: a rotation as degrees that
//! keep their own angles, a union's dropdown of cases and its case's rows, a readout, a bit set's checkboxes, an asset
//! field taking a file dropped on it, a row of buttons, and rows of its own added after a component's (extras). Edits
//! are made the way the widgets make them. No window needed. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const UIManager = @import("../../UI/UIManager.zig");
const Inspector = @import("../../UI/Inspector.zig");
const WidgetActions = @import("../../UI/WidgetActions.zig");
const MathTypes = @import("../../Math/MathTypes.zig");
const Vec3 = MathTypes.Vec3;
const Quat = MathTypes.Quat;

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const TextComponent = EntityComponents.TextComponent;
const SurfaceComponent = EntityComponents.SurfaceComponent;
const ColliderComponent = EntityComponents.ColliderComponent;
const TransformComponent = EntityComponents.TransformComponent;
const AttribComponent = EntityComponents.AttribComponent;
const UUIDComponent = EntityComponents.UUIDComponent;
const SelectedTag = EntityComponents.SelectedTag;
const FileRefComponent = EntityComponents.FileRefComponent;

const NO_SCRIPTS = @import("../../UI/Widgets.zig").Options{ .StockScripts = false };

const TestWorld = struct {
    mEngineContext: *EngineContext,
    mScene: Scene = undefined,
    mPanel: Entity = .uninit,
    mObject: Entity = .uninit,

    /// With the asset manager, for asset fields
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
        self.mScene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
        self.mPanel = try self.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
        self.mObject = try self.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        const engine_allocator = engine_context.EngineAllocator();
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        //the asset manager, minus the default assets Init never set up (see PendingDeleteTests)
        const asset_manager = &engine_context.mAssetManager;
        asset_manager.mECSManager.Deinit(engine_context);
        asset_manager.mUUIDToWorldID.deinit(engine_allocator);
        asset_manager.mEventManager.Deinit(engine_allocator);
        asset_manager.mCWDPath.deinit(engine_allocator);
        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    fn Builder(self: *TestWorld, comptime component_type: type) Inspector.Builder {
        return Inspector.ForComponent(self.mEngineContext, self.mPanel, self.mPanel, self.mObject, component_type, NO_SCRIPTS);
    }

    fn ShowFields(self: *TestWorld) !void {
        try self.mEngineContext.mUIManager.mBindingSystem.Update(self.mEngineContext);
    }

    fn ProcessUIEvents(self: *TestWorld) !void {
        try self.mEngineContext.mUIManager.ProcessUIEvents(self.mEngineContext, .{});
    }

    fn Row(self: *TestWorld, index: usize) Entity {
        var rows = self.mPanel.GetIterator(.Child);
        var row = rows.next().?;
        for (0..index) |_| row = rows.next().?;
        return row;
    }

    /// The `part`th thing in the `index`th row: 0 is its label
    fn Part(self: *TestWorld, index: usize, part: usize) Entity {
        var parts = self.Row(index).GetIterator(.Child);
        var entity = parts.next().?;
        for (0..part) |_| entity = parts.next().?;
        return entity;
    }

    fn RowCount(self: *TestWorld) usize {
        var count: usize = 0;
        var rows = self.mPanel.GetIterator(.Child);
        while (rows.next()) |_| count += 1;
        return count;
    }
};

/// A rotation row's numbers, X, Y, Z
fn Degrees(row: Entity) [3]f32 {
    var degrees: [3]f32 = undefined;
    var axis: usize = 0;
    var children = row.GetIterator(.Child);
    while (children.next()) |child| {
        const attrib = child.GetComponent(AttribComponent) orelse continue;
        degrees[axis] = attrib.mData.float32;
        axis += 1;
    }
    return degrees;
}

fn SetDegrees(world: *TestWorld, row: Entity, degrees: [3]f32) !void {
    var axis: usize = 0;
    var children = row.GetIterator(.Child);
    while (children.next()) |child| {
        const attrib = child.GetComponent(AttribComponent) orelse continue;
        attrib.mData.SetFromFloat(degrees[axis]);
        axis += 1;
    }
    //one of the numbers dragged: its ValueChanged reaches the row too
    try world.mEngineContext.mUIManager.SendToChain(world.mEngineContext, row, .ValueChanged);
    try world.ProcessUIEvents();
}

fn SameRotation(a: Quat(f32), b: Quat(f32)) bool {
    return @abs(a.w * b.w + a.x * b.x + a.y * b.y + a.z * b.z) > 1 - 1e-4;
}

test "a rotation is shown in degrees, an edit is written from all three, and the numbers keep their own angles" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const transform = world.mObject.GetComponent(TransformComponent).?;
    transform._Rotation = Quat(f32).FromDegrees(.{ .x = 0, .y = 45, .z = 0 });
    var ui = world.Builder(TransformComponent);
    try ui.Rotation(&transform._Rotation, "Rotation", .{});
    const row = world.Part(0, 1);
    try std.testing.expectApproxEqAbs(@as(f32, 45), Degrees(row)[1], 0.01);

    try SetDegrees(world, row, .{ 10, 20, 30 });
    const written = world.mObject.GetComponent(TransformComponent).?._Rotation;
    try std.testing.expect(SameRotation(Quat(f32).FromDegrees(.{ .x = 10, .y = 20, .z = 30 }), written));

    //the same rotation in other angles: kept as typed, not turned back into its usual angles
    try SetDegrees(world, row, .{ 180, 180, 180 });
    try world.ShowFields();
    try std.testing.expectApproxEqAbs(@as(f32, 180), Degrees(row)[0], 0.01);

    //changed by something else: shown again
    world.mObject.GetComponent(TransformComponent).?._Rotation = Quat(f32).FromDegrees(.{ .x = 0, .y = 0, .z = 90 });
    try world.ShowFields();
    try std.testing.expectApproxEqAbs(@as(f32, 90), Degrees(row)[2], 0.01);
}

test "a union is a dropdown of its cases and its case's rows, and picking another starts it at its default" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const attrib = try world.mObject.AddComponent(engine_context, AttribComponent{ .mData = .{ .float32 = 2.5 } });
    var ui = world.Builder(AttribComponent);
    try ui.Union(&attrib.mData, "Value", .{});

    //the dropdown, then the case's number
    try std.testing.expectEqual(@as(usize, 2), world.RowCount());
    const dropdown = world.Part(0, 1);
    try std.testing.expectEqualStrings("float32", UIManager.LabelOf(dropdown).?.GetComponent(TextComponent).?.mText.items);
    try std.testing.expectEqualStrings("float32", world.Part(1, 0).GetComponent(TextComponent).?.mText.items);
    try std.testing.expectEqual(@as(f32, 2.5), world.Part(1, 1).GetComponent(AttribComponent).?.mData.float32);

    //bool picked: false, and the inspector asked to be built again for its rows
    try WidgetActions.TogglePopup(engine_context, dropdown);
    var choices = WidgetActions.PopupOf(dropdown).?.GetIterator(.Child);
    var choice = choices.next().?;
    for (0..3) |_| choice = choices.next().?;
    try WidgetActions.Choose(engine_context, choice);
    try world.ProcessUIEvents();
    try std.testing.expectEqual(AttribComponent.ValueTypes{ .bool = false }, world.mObject.GetComponent(AttribComponent).?.mData);
    try std.testing.expect(engine_context.mUIManager.mBindingSystem.TakeRebuild(world.mPanel));
}

fn ShowId(id: u64, buffer: []u8) []const u8 {
    return std.fmt.bufPrint(buffer, "{d}", .{id}) catch "?";
}

test "a readout shows its field as it changes, a bit set is a checkbox a bit, and buttons sit in a row" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const uuid = world.mObject.GetComponent(UUIDComponent).?;
    var uuid_ui = world.Builder(UUIDComponent);
    try uuid_ui.Readout(&uuid.ID, "UUID", ShowId);
    const shown = world.Part(0, 1);
    try std.testing.expectEqual(uuid.ID, try std.fmt.parseInt(u64, shown.GetComponent(TextComponent).?.mText.items, 10));
    world.mObject.GetComponent(UUIDComponent).?.ID = 7;
    try world.ShowFields();
    try std.testing.expectEqualStrings("7", shown.GetComponent(TextComponent).?.mText.items);

    const collider = try world.mObject.AddComponent(engine_context, ColliderComponent{});
    var collider_ui = world.Builder(ColliderComponent);
    try collider_ui.Flags(&collider.mCollisionFilter.CategoryMask, "Category Mask", .{});
    const grid = world.Part(1, 1);
    var boxes: [32]Entity = undefined;
    var count: usize = 0;
    var children = grid.GetIterator(.Child);
    while (children.next()) |checkbox| : (count += 1) {
        var parts = checkbox.GetIterator(.Child);
        boxes[count] = parts.next().?;
    }
    try std.testing.expectEqual(@as(usize, 32), count);
    _ = try boxes[3].AddComponent(engine_context, SelectedTag{});
    try engine_context.mUIManager.SendToChain(engine_context, boxes[3], .ValueChanged);
    try world.ProcessUIEvents();
    try std.testing.expect(world.mObject.GetComponent(ColliderComponent).?.mCollisionFilter.CategoryMask.isSet(3));
    try std.testing.expect(!world.mObject.GetComponent(ColliderComponent).?.mCollisionFilter.CategoryMask.isSet(4));

    const buttons = try collider_ui.Buttons(&.{ "Preview", "Stop" });
    try std.testing.expectEqual(@as(usize, 3), world.RowCount());
    try std.testing.expectEqualStrings("Stop", UIManager.LabelOf(buttons[1]).?.GetComponent(TextComponent).?.mText.items);
}

test "an asset field shows its asset's name, and takes a dropped file of a kind it accepts" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const surface = try world.mObject.AddComponent(engine_context, SurfaceComponent{});
    var ui = world.Builder(SurfaceComponent);
    try ui.Asset(&surface.mTexture, "Texture", &.{".png"}, .{ .Thumbnail = true });
    const thumbnail = world.Part(0, 1);
    const box = world.Part(0, 2);
    try world.ShowFields();
    try std.testing.expectEqualStrings("None", UIManager.LabelOf(box).?.GetComponent(TextComponent).?.mText.items);

    //something carrying a file, dropped on the box: a script is turned down, a picture taken
    const carried = try world.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try carried.AddComponent(engine_context, try FileRefComponent.Init(engine_context, "Mover.zig", .Prj));
    try engine_context.mUIManager.OnPointerEvent(engine_context, .{ .PointerDropped = .{ .mEntity = box, .mSource = carried, .mPosition = .{ .x = 0, .y = 0, .z = 0 } } });
    try std.testing.expect(world.mObject.GetComponent(SurfaceComponent).?.mTexture.mID == @import("../../ECSObjects/AssetHandle.zig").NullObject);

    const picture = try world.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try picture.AddComponent(engine_context, try FileRefComponent.Init(engine_context, "src/Imaginengion/EngineAssets/textures/White.png", .Eng));
    try engine_context.mUIManager.OnPointerEvent(engine_context, .{ .PointerDropped = .{ .mEntity = box, .mSource = picture, .mPosition = .{ .x = 0, .y = 0, .z = 0 } } });
    const texture = world.mObject.GetComponent(SurfaceComponent).?.mTexture;
    try std.testing.expect(texture.mID != @import("../../ECSObjects/AssetHandle.zig").NullObject);
    try world.ShowFields();
    try std.testing.expectEqualStrings("White", UIManager.LabelOf(box).?.GetComponent(TextComponent).?.mText.items);
    try std.testing.expectEqual(texture.mID, thumbnail.GetComponent(SurfaceComponent).?.mTexture.mID);
}

/// Rows of its own after a component's, for RenderComponentWith
const Extras = struct {
    mCalls: usize = 0,
    mLastType: []const u8 = "",

    pub fn After(self: *Extras, comptime component_type: type, ui: *Inspector.Builder, _: *component_type, _: Entity) !void {
        self.mCalls += 1;
        self.mLastType = component_type.Name;
        try ui.Note("extra");
    }
};

test "extras add rows after a component's own, and for a component with no UIRender too" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    var extras = Extras{};
    try Inspector.RenderComponentWith(engine_context, world.mPanel, world.mPanel, world.mObject, UUIDComponent, NO_SCRIPTS, &extras);
    try std.testing.expectEqual(@as(usize, 1), extras.mCalls);
    try std.testing.expectEqualStrings("UUIDComponent", extras.mLastType);
    try std.testing.expectEqualStrings("extra", world.Row(world.RowCount() - 1).GetComponent(TextComponent).?.mText.items);
}
