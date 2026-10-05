//! The inspector (UI/Inspector.zig) and the binding system (UI/BindingSystem.zig) on real components: each kind of field
//! shown on its widget and written back from it, conversions and OnChange, a struct with no UIRender showing nothing,
//! the after-edit dirty tags, a field that asks for the inspector to be built again, and a binding still finding its
//! field after the component has moved in memory. Edits are made the way the widgets make them: a value on the widget and
//! its event. No window needed. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const UIManager = @import("../../UI/UIManager.zig");
const Inspector = @import("../../UI/Inspector.zig");
const WidgetActions = @import("../../UI/WidgetActions.zig");
const MathTypes = @import("../../Math/MathTypes.zig");
const Vec4 = MathTypes.Vec4;

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const QuadComponent = EntityComponents.QuadComponent;
const TextComponent = EntityComponents.TextComponent;
const ColliderComponent = EntityComponents.ColliderComponent;
const TransformComponent = EntityComponents.TransformComponent;
const TransformDirtyTag = EntityComponents.TransformDirtyTag;
const AttribComponent = EntityComponents.AttribComponent;
const SelectedTag = EntityComponents.SelectedTag;

const NO_SCRIPTS = @import("../../UI/Widgets.zig").Options{ .StockScripts = false };

const TestWorld = struct {
    mEngineContext: *EngineContext,
    mScene: Scene = undefined,
    /// what the rows go in, and what is built again
    mPanel: Entity = .uninit,
    mObject: Entity = .uninit,

    fn Init() !*TestWorld {
        const self = try std.heap.page_allocator.create(TestWorld);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        try engine_context.mUIManager.Init(engine_context.EngineAllocator());
        try engine_context.mEditorWorld.Init(engine_context.EngineAllocator());
        self.mScene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
        self.mPanel = try self.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
        self.mObject = try self.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    fn Builder(self: *TestWorld, comptime component_type: type) Inspector.Builder {
        return Inspector.ForComponent(self.mEngineContext, self.mPanel, self.mPanel, self.mObject, component_type, NO_SCRIPTS);
    }

    /// The bindings put their fields on their widgets, as they do once a frame
    fn ShowFields(self: *TestWorld) !void {
        try self.mEngineContext.mUIManager.mBindingSystem.Update(self.mEngineContext);
    }

    /// The frame's UI events handed out, which is when edits are written
    fn ProcessUIEvents(self: *TestWorld) !void {
        try self.mEngineContext.mUIManager.ProcessUIEvents(self.mEngineContext, .{});
    }

    /// The widget of the `index`th row: what comes after its label
    fn Widget(self: *TestWorld, index: usize) Entity {
        var rows = self.mPanel.GetIterator(.Child);
        var row = rows.next().?;
        for (0..index) |_| row = rows.next().?;
        var parts = row.GetIterator(.Child);
        _ = parts.next().?; //the label
        return parts.next().?;
    }

    fn RowCount(self: *TestWorld) usize {
        var count: usize = 0;
        var rows = self.mPanel.GetIterator(.Child);
        while (rows.next()) |_| count += 1;
        return count;
    }
};

fn FirstChild(entity: Entity) Entity {
    var children = entity.GetIterator(.Child);
    return children.next().?;
}

/// An edit to a number field: its value, and the ValueChanged it sends
fn EditNumber(world: *TestWorld, field: Entity, value: f64) !void {
    field.GetComponent(AttribComponent).?.mData.SetFromFloat(value);
    try world.mEngineContext.mUIManager.SendToChain(world.mEngineContext, field, .ValueChanged);
    try world.ProcessUIEvents();
}

var gChanges: usize = 0;
fn CountChange(_: *anyopaque) void {
    gChanges += 1;
}

fn Double(value: f64) f64 {
    return value * 2;
}
fn Half(value: f64) f64 {
    return value / 2;
}

test "numbers, vectors, bools and colors show their fields and write edits back, through conversions" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const quad = try world.mObject.AddComponent(engine_context, QuadComponent{ .mBorderWidth = 2, .mSize = .{ .x = 3, .y = 4 } });
    var ui = world.Builder(QuadComponent);
    try ui.Float(&quad.mBorderWidth, "Border Width", .{ .Convert = .{ .ToShown = Double, .FromShown = Half }, .OnChange = CountChange });
    try ui.Vec2Field(&quad.mSize, "Size", .{});
    try ui.Bool(&quad.mShouldRender, "Should Render?", .{});
    try ui.Color(&quad.mBorderColor, "Border Color", .{});

    //shown as built, converted
    const border = world.Widget(0);
    try std.testing.expectEqual(@as(f32, 4), border.GetComponent(AttribComponent).?.mData.float32);
    //written back converted, with the field's OnChange after
    gChanges = 0;
    try EditNumber(world, border, 10);
    try std.testing.expectEqual(@as(f32, 5), world.mObject.GetComponent(QuadComponent).?.mBorderWidth);
    try std.testing.expectEqual(@as(usize, 1), gChanges);

    //a field changed by code: its widget catches up
    world.mObject.GetComponent(QuadComponent).?.mSize.y = 9;
    try world.ShowFields();
    var size_numbers = world.Widget(1).GetIterator(.Child);
    _ = size_numbers.next(); //the X box
    _ = size_numbers.next(); //x
    _ = size_numbers.next(); //the Y box
    const size_y = size_numbers.next().?;
    try std.testing.expectEqual(@as(f32, 9), size_y.GetComponent(AttribComponent).?.mData.float32);
    try EditNumber(world, size_y, 7);
    try std.testing.expectEqual(@as(f32, 7), world.mObject.GetComponent(QuadComponent).?.mSize.y);

    //a bool is a checkbox's box
    const box = FirstChild(world.Widget(2));
    try std.testing.expect(box.HasComponent(SelectedTag));
    try WidgetActions.Toggle(engine_context, box);
    try world.ProcessUIEvents();
    try std.testing.expect(!world.mObject.GetComponent(QuadComponent).?.mShouldRender);

    //a color is a color field
    const color = world.Widget(3);
    try WidgetActions.SetColor(engine_context, color, .{ .x = 0.5, .y = 0.25, .z = 1, .w = 1 });
    try world.ProcessUIEvents();
    try std.testing.expectEqual(@as(f32, 0.25), world.mObject.GetComponent(QuadComponent).?.mBorderColor.y);
    world.mObject.GetComponent(QuadComponent).?.mBorderColor = .{ .x = 0, .y = 0, .z = 0, .w = 1 };
    try world.ShowFields();
    try std.testing.expectEqual(@as(f32, 0), WidgetActions.ColorOf(color).x);
}

test "an enum is a dropdown, text a text field, and a struct with no UIRender shows nothing" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const collider = try world.mObject.AddComponent(engine_context, ColliderComponent{ .mShape = .Sphere });
    var ui = world.Builder(ColliderComponent);
    try ui.Enum(ColliderComponent.Shapes, &collider.mShape, "Shape", .{ .Rebuilds = true });
    //no UIRender on it: no rows
    try ui.Struct(&collider.mCollisionFilter, "Filter");
    try std.testing.expectEqual(@as(usize, 1), world.RowCount());

    const dropdown = world.Widget(0);
    try std.testing.expectEqualStrings("Sphere", UIManager.LabelOf(dropdown).?.GetComponent(TextComponent).?.mText.items);
    //picked from its list: written, and the inspector asked to be built again, once
    const box_index = std.mem.indexOfScalar(ColliderComponent.Shapes, std.enums.values(ColliderComponent.Shapes), .Box).?;
    try WidgetActions.TogglePopup(engine_context, dropdown);
    var rows = WidgetActions.PopupOf(dropdown).?.GetIterator(.Child);
    var row = rows.next().?;
    for (0..box_index) |_| row = rows.next().?;
    try WidgetActions.Choose(engine_context, row);
    try world.ProcessUIEvents();
    try std.testing.expectEqual(ColliderComponent.Shapes.Box, world.mObject.GetComponent(ColliderComponent).?.mShape);
    try std.testing.expect(engine_context.mUIManager.mBindingSystem.TakeRebuild(world.mPanel));
    try std.testing.expect(!engine_context.mUIManager.mBindingSystem.TakeRebuild(world.mPanel));

    //set by code: shown without anyone hearing about it
    world.mObject.GetComponent(ColliderComponent).?.mShape = .Sphere;
    try world.ShowFields();
    try std.testing.expectEqualStrings("Sphere", UIManager.LabelOf(dropdown).?.GetComponent(TextComponent).?.mText.items);
    try std.testing.expect(!engine_context.mUIManager.mBindingSystem.TakeRebuild(world.mPanel));

    //text
    const text = try world.mObject.AddComponent(engine_context, TextComponent{});
    try text.SetText(engine_context, "Hello");
    var text_ui = world.Builder(TextComponent);
    try text_ui.Text(&text.mText, "Text", .{});
    const typed = UIManager.LabelOf(world.Widget(1)).?;
    try std.testing.expectEqualStrings("Hello", typed.GetComponent(TextComponent).?.mText.items);
    const focus = &engine_context.mUIManager.mFocusSystem;
    _ = try focus.Focus(engine_context, typed);
    try focus.OnTextTyped(engine_context, "!");
    try focus.OnKeyPressed(engine_context, .{ ._InputCode = .RETURN, ._Repeat = 0 });
    try world.ProcessUIEvents();
    try std.testing.expectEqualStrings("Hello!", world.mObject.GetComponent(TextComponent).?.mText.items);
}

test "a binding finds its field after the component has moved, and an edit sets the component's dirty tags" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const transform = world.mObject.GetComponent(TransformComponent).?;
    var ui = world.Builder(TransformComponent);
    try ui.Vec3Field(&transform._Translation, "Translation", .{});

    //enough new entities that the transforms' storage grows and moves
    for (0..200) |_| _ = try world.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
    try world.mObject.SetTranslation(engine_context, .{ .x = 6, .y = 0, .z = 0 });
    if (world.mObject.HasComponent(TransformDirtyTag)) try world.mObject.RemoveComponentSync(engine_context, TransformDirtyTag);
    try world.ShowFields();
    var numbers = world.Widget(0).GetIterator(.Child);
    _ = numbers.next(); //the X box
    const x = numbers.next().?;
    try std.testing.expectEqual(@as(f32, 6), x.GetComponent(AttribComponent).?.mData.float32);

    try EditNumber(world, x, 8);
    try std.testing.expectEqual(@as(f32, 8), world.mObject.GetComponent(TransformComponent).?.GetTranslation().x);
    try std.testing.expect(world.mObject.HasComponent(TransformDirtyTag));
}

test "fields read and write each type as a value" {
    var whole: i32 = -3;
    const int_access = Inspector.AccessFor(i32);
    try std.testing.expectEqual(@as(f64, -3), int_access.Read(&whole).Number);
    try int_access.Write(undefined, &whole, .{ .Number = 4.6 });
    try std.testing.expectEqual(@as(i32, 5), whole);

    var count: u32 = 2;
    try Inspector.AccessFor(u32).Write(undefined, &count, .{ .Number = -10 });
    try std.testing.expectEqual(@as(u32, 0), count);
}
