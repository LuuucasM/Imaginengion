//! The popup system on real entities: popups starting closed, opening against an entity or a point, stacking for
//! submenus, closing on presses outside them, and what closing does to a text field inside one. Presses come through
//! the pointer system the way the editor hands them over, and each frame runs layout, the popup system and world
//! transforms in the editor's order. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const UIEvent = @import("../../Events/UIEventData.zig").UIEvent;
const Vec2 = @import("../../Math/MathTypes.zig").Vec2;
const LayoutSystem = @import("../../UI/LayoutSystem.zig");
const PhysicsManager = @import("../../Physics/PhysicsManager.zig");

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const UIComponents = @import("../../ECSComponents/UIComponents.zig");
const PopupComponent = UIComponents.PopupComponent;
const UIElementComponent = EntityComponents.UIElementComponent;
const UIManager = @import("../../UI/UIManager.zig");
const LayoutComponent = EntityComponents.LayoutComponent;
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const LayoutHiddenTag = EntityComponents.LayoutHiddenTag;
const ShapeComponent = EntityComponents.ShapeComponent;
const SurfaceComponent = EntityComponents.SurfaceComponent;
const TextComponent = EntityComponents.TextComponent;
const TextInputComponent = UIComponents.TextInputComponent;
const TransformComponent = EntityComponents.TransformComponent;
const SComponents = @import("../../ECSComponents/SComponents.zig");
const SceneComponent = SComponents.SceneComponent;
const StackPosComponent = SComponents.StackPosComponent;

const SEventData = @import("../../Events/SManagerData.zig");
const EEventData = @import("../../Events/EManagerData.zig");
const ECSEventData = @import("../../Events/ECSEventData.zig");

const eps: f32 = 0.01;

/// A panel with a button on it, a menu with a "New" row and a field in it, a submenu that hangs beside "New", and a
/// dropdown list
const TestWorld = struct {
    mEngineContext: *EngineContext,
    mPanel: Entity = .uninit,
    mButton: Entity = .uninit,
    mMenu: Entity = .uninit,
    mNewRow: Entity = .uninit,
    mField: Entity = .uninit,
    mSubmenu: Entity = .uninit,
    mDropdown: Entity = .uninit,

    fn Init() !*TestWorld {
        const self = try std.heap.page_allocator.create(TestWorld);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        try engine_context.mUIManager.Init(engine_context.EngineAllocator());
        try engine_context.mEditorWorld.Init(engine_context.EngineAllocator());

        const scene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
        scene.GetComponent(SceneComponent).?.mLayoutArea = .{ .x = 1920, .y = 1080 };

        self.mPanel = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
        self.mButton = try self.mPanel.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
        try self.mButton.SetTranslation(engine_context, .{ .x = 100, .y = 200, .z = 0 });
        _ = try self.mButton.AddComponent(engine_context, ShapeComponent.MakeQuad(.{ .Size = .{ .x = 100, .y = 20 } }));
        _ = try self.mButton.AddComponent(engine_context, SurfaceComponent{});

        //80 x 60, hanging below what opens it (the default)
        self.mMenu = try Popup(engine_context, scene, .{}, 80, 60);
        _ = try self.mMenu.AddComponent(engine_context, LayoutComponent{});
        self.mNewRow = try self.mMenu.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
        _ = try self.mNewRow.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fixed = 80 }, .mHeight = .{ .Fixed = 20 } });
        self.mField = try self.mMenu.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
        _ = try self.mField.AddComponent(engine_context, TextComponent{});
        _ = try self.mField.AddComponent(engine_context, SurfaceComponent{});
        try AddUI(engine_context, self.mField, TextInputComponent{});

        //50 x 40, beside what opens it, top edges lined up
        self.mSubmenu = try Popup(engine_context, scene, .{ .mPlacement = .{ .Anchor = .{ .x = 1, .y = 1 }, .Pivot = .{ .x = -1, .y = 1 } } }, 50, 40);
        self.mDropdown = try Popup(engine_context, scene, .{}, 100, 50);
        return self;
    }

    fn Popup(engine_context: *EngineContext, scene: Scene, popup: PopupComponent, width: f32, height: f32) !Entity {
        const entity = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
        try AddUI(engine_context, entity, popup);
        _ = try entity.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fixed = width }, .mHeight = .{ .Fixed = height } });
        return entity;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        engine_context.mPointerSystem.Deinit(engine_context.EngineAllocator());
        engine_context.mPointerEventManager.Deinit(engine_context.EngineAllocator());
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    /// The editor's frame from layout on: layout, then the popup system, then world transforms
    fn Frame(self: *TestWorld) !void {
        const engine_context = self.mEngineContext;
        const world = &engine_context.mEditorWorld;
        try LayoutSystem.UpdateLayouts(world, engine_context);
        try engine_context.mUIManager.mPopupSystem.Update(engine_context, world);
        try engine_context.mUIManager.mFocusSystem.Update(engine_context);
        try PhysicsManager.UpdateWorldTransforms(world, engine_context);
    }

    /// A left press over `target`, handed out like the editor does: pointer, then popups, then focus
    fn Press(self: *TestWorld, target: ?Entity) !void {
        const engine_context = self.mEngineContext;
        try engine_context.mPointerSystem.Update(engine_context, .{ .Target = target });
        try engine_context.mPointerSystem.OnPressed(engine_context, .BUTTON_LEFT);
        try engine_context.mUIManager.mPopupSystem.OnPressed(engine_context, &engine_context.mPointerSystem);
        try engine_context.mUIManager.mFocusSystem.OnPressed(engine_context, &engine_context.mPointerSystem, .BUTTON_LEFT);
        try engine_context.mPointerSystem.OnReleased(engine_context, .BUTTON_LEFT);
    }

    fn Open(self: *TestWorld, popup: Entity, opener: Entity) !void {
        try self.mEngineContext.mUIManager.mPopupSystem.Open(self.mEngineContext, popup, .{ .Opener = opener });
    }

    /// The popup events since the last call, the popup each was for, in order. Only the popup's own event of the ones
    /// sent up its chain
    fn TakeEvents(self: *TestWorld) ![]UIEvent {
        const engine_context = self.mEngineContext;
        const queued = engine_context.mUIManager.mEventManager.mEventsArray.getPtr(.UI);
        var taken: std.ArrayList(UIEvent) = .empty;
        for (queued.items) |event| {
            const entity_event = switch (event) {
                .Entity => |e| e,
                else => continue,
            };
            switch (entity_event.mEvent) {
                .PopupOpened, .PopupClosed => |e| if (entity_event.mEntity.mID == e.mTarget.mID) try taken.append(engine_context.FrameAllocator(), entity_event.mEvent),
                else => {},
            }
        }
        queued.clearRetainingCapacity();
        return taken.items;
    }

    /// EditorProgram.OnUpdate's end of frame for the editor world, where deletes happen
    fn EndFrame(self: *TestWorld) !void {
        const engine_context = self.mEngineContext;
        const world = &engine_context.mEditorWorld;
        var callback_list: std.DoublyLinkedList = .{};
        try world.ProcessEvents(SEventData, .EndOfFrame, engine_context, &callback_list);
        try world.ProcessEvents(EEventData, .EndOfFrame, engine_context, &callback_list);
        try world.ProcessEvents(ECSEventData, .EndOfFrame, engine_context, &callback_list);
    }
};

/// Gives `entity` a UI element (if it has none yet) and `component` on it
fn AddUI(engine_context: *EngineContext, entity: Entity, component: anytype) !void {
    if (!entity.HasComponent(UIElementComponent)) _ = try entity.AddComponent(engine_context, UIElementComponent{});
    _ = try UIManager.ElementOf(entity).?.AddComponent(engine_context, component);
}

/// Exactly these popups are open, bottom of the stack first, and they are the ones shown
fn ExpectOpen(world: *TestWorld, expected: []const Entity) !void {
    const open = world.mEngineContext.mUIManager.mPopupSystem.OpenPopups();
    try std.testing.expectEqual(expected.len, open.len);
    for (expected, open) |entity, popup| try std.testing.expectEqual(entity.mID, popup.mPopup.mID);
    for ([_]Entity{ world.mMenu, world.mSubmenu, world.mDropdown }) |popup| {
        var is_open = false;
        for (expected) |entity| is_open = is_open or entity.mID == popup.mID;
        try std.testing.expectEqual(!is_open, popup.GetComponent(LayoutItemComponent).?.mCollapsed);
    }
}

/// Exactly these events, in order: each popup opened (true) or closed (false)
fn ExpectEvents(events: []const UIEvent, expected: []const struct { Entity, bool }) !void {
    try std.testing.expectEqual(expected.len, events.len);
    for (expected, events) |pair, event| {
        switch (event) {
            .PopupOpened => |e| {
                try std.testing.expect(pair[1]);
                try std.testing.expectEqual(pair[0].mID, e.mTarget.mID);
            },
            .PopupClosed => |e| {
                try std.testing.expect(!pair[1]);
                try std.testing.expectEqual(pair[0].mID, e.mTarget.mID);
            },
            else => unreachable,
        }
    }
}

fn ExpectAt(entity: Entity, x: f32, y: f32) !void {
    const translation = entity.GetComponent(TransformComponent).?.GetTranslation();
    try std.testing.expectApproxEqAbs(x, translation.x, eps);
    try std.testing.expectApproxEqAbs(y, translation.y, eps);
}

test "popups start closed, hidden and out of the pointer's way" {
    const world = try TestWorld.Init();
    defer world.Deinit();

    try world.Frame();
    try ExpectOpen(world, &.{});
    try world.Frame();
    try std.testing.expect(world.mMenu.HasComponent(LayoutHiddenTag));
    try std.testing.expect(world.mNewRow.HasComponent(LayoutHiddenTag));
}

test "a popup opens against its opener's rectangle, and follows it" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    try world.Frame();

    try world.Open(world.mMenu, world.mButton);
    try ExpectEvents(try world.TakeEvents(), &.{.{ world.mMenu, true }});
    try world.Frame();
    try ExpectOpen(world, &.{world.mMenu});
    try std.testing.expect(!world.mMenu.HasComponent(LayoutHiddenTag));
    //the button is 100 x 20 around (100, 200): the menu's top left on its bottom left, so its middle is 40 right of
    //the button's left edge and 30 below its bottom edge
    try ExpectAt(world.mMenu, 90, 160);

    try world.mButton.SetTranslation(world.mEngineContext, .{ .x = 300, .y = 200, .z = 0 });
    try world.Frame();
    try world.Frame();
    try ExpectAt(world.mMenu, 290, 160);
}

test "a popup opened at a point hangs from that point" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    try world.Frame();

    try world.mEngineContext.mUIManager.mPopupSystem.Open(world.mEngineContext, world.mMenu, .{ .Point = .{ .x = 300, .y = 300 } });
    try world.Frame();
    try ExpectAt(world.mMenu, 340, 270);
}

test "a popup opened from inside another goes on top of it, one opened from outside closes the others" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    try world.Frame();

    try world.Open(world.mMenu, world.mButton);
    try world.Frame();
    try world.Frame();
    try world.Open(world.mSubmenu, world.mNewRow);
    try world.Frame();
    try world.Frame();
    try ExpectOpen(world, &.{ world.mMenu, world.mSubmenu });
    //beside the New row, the menu's top row (80 x 20 around (90, 180)), top edges lined up
    try ExpectAt(world.mSubmenu, 155, 170);
    _ = try world.TakeEvents();

    try world.Open(world.mDropdown, world.mButton);
    try ExpectOpen(world, &.{world.mDropdown});
    try ExpectEvents(try world.TakeEvents(), &.{ .{ world.mSubmenu, false }, .{ world.mMenu, false }, .{ world.mDropdown, true } });

    //opening an open one again only closes what is above it
    try world.Open(world.mMenu, world.mButton);
    try world.Open(world.mSubmenu, world.mNewRow);
    _ = try world.TakeEvents();
    try world.Open(world.mMenu, world.mButton);
    try ExpectOpen(world, &.{world.mMenu});
    try ExpectEvents(try world.TakeEvents(), &.{.{ world.mSubmenu, false }});
}

test "a press closes the popups above the one it lands in or whose opener it lands on, and every popup when it lands outside them" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    try world.Frame();
    try world.Open(world.mMenu, world.mButton);
    try world.Open(world.mSubmenu, world.mNewRow);
    _ = try world.TakeEvents();

    //on the row that opened the submenu: it counts as inside the submenu, so both stay
    try world.Press(world.mNewRow);
    try ExpectOpen(world, &.{ world.mMenu, world.mSubmenu });

    //on the menu itself: only the submenu goes
    try world.Press(world.mMenu);
    try ExpectOpen(world, &.{world.mMenu});
    try ExpectEvents(try world.TakeEvents(), &.{.{ world.mSubmenu, false }});

    //on the button that opened the menu: it stays, for the button's own script to close
    try world.Press(world.mButton);
    try ExpectOpen(world, &.{world.mMenu});

    //anywhere else, over something or over nothing
    try world.Press(world.mPanel);
    try ExpectOpen(world, &.{});
    try world.Open(world.mDropdown, world.mButton);
    try world.Press(null);
    try ExpectOpen(world, &.{});
}

test "Close takes the ones above with it, CloseTop only the top one" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const popups = &world.mEngineContext.mUIManager.mPopupSystem;
    try world.Frame();

    try world.Open(world.mMenu, world.mButton);
    try world.Open(world.mSubmenu, world.mNewRow);
    try popups.CloseTop(world.mEngineContext);
    try ExpectOpen(world, &.{world.mMenu});

    try world.Open(world.mSubmenu, world.mNewRow);
    _ = try world.TakeEvents();
    try popups.Close(world.mEngineContext, world.mMenu);
    try ExpectOpen(world, &.{});
    //the top one first
    try ExpectEvents(try world.TakeEvents(), &.{ .{ world.mSubmenu, false }, .{ world.mMenu, false } });

    //closing what isn't open does nothing
    try popups.Close(world.mEngineContext, world.mMenu);
    try popups.CloseAll(world.mEngineContext);
    try std.testing.expectEqual(@as(usize, 0), (try world.TakeEvents()).len);
}

test "closing a popup ends the edit of a text field in it, keeping it" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    try world.Frame();

    try world.Open(world.mMenu, world.mButton);
    try world.Press(world.mField);
    try std.testing.expect(engine_context.mUIManager.mFocusSystem.Focused() != null);
    try engine_context.mUIManager.mFocusSystem.OnTextTyped(engine_context, "hi");

    try engine_context.mUIManager.mPopupSystem.CloseAll(engine_context);
    try std.testing.expect(engine_context.mUIManager.mFocusSystem.Focused() == null);
    try std.testing.expectEqualStrings("hi", world.mField.GetComponent(TextComponent).?.mText.items);
}

test "a deleted popup is let go of, along with the ones opened from it" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    try world.Frame();

    try world.Open(world.mMenu, world.mButton);
    try world.Open(world.mSubmenu, world.mNewRow);
    _ = try world.TakeEvents();
    try world.mMenu.Delete(world.mEngineContext);
    try world.EndFrame();

    try world.Frame();
    try std.testing.expectEqual(@as(usize, 0), world.mEngineContext.mUIManager.mPopupSystem.OpenPopups().len);
    try std.testing.expect(world.mSubmenu.GetComponent(LayoutItemComponent).?.mCollapsed);
    try ExpectEvents(try world.TakeEvents(), &.{.{ world.mSubmenu, false }});
}

test "the top popup's turn at Escape is its scene's place in the stack" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const popups = &world.mEngineContext.mUIManager.mPopupSystem;

    try std.testing.expect(popups.TopStackPos() == null);
    try world.Open(world.mMenu, world.mButton);
    const scene = world.mMenu.GetComponent(EntityComponents.EntitySceneComponent).?.mScene;
    try std.testing.expectEqual(scene.GetComponent(StackPosComponent).?.mPosition, popups.TopStackPos().?);
}

test "Escape goes to the top popup, unless a text input in the same scene has the keyboard; other keys only to the text input" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const ui_manager = &engine_context.mUIManager;
    const stack_pos = world.mMenu.GetComponent(EntityComponents.EntitySceneComponent).?.mScene.GetComponent(StackPosComponent).?.mPosition;
    try world.Frame();

    //nothing open, nothing typed into: the UI takes nothing
    try std.testing.expect(ui_manager.KeyTakerFor(.ESCAPE) == null);

    try world.Open(world.mMenu, world.mButton);
    const escape = ui_manager.KeyTakerFor(.ESCAPE).?;
    try std.testing.expectEqual(.Popup, escape.Kind);
    try std.testing.expectEqual(stack_pos, escape.StackPos);
    //the world whose scene stack that is a place in
    try std.testing.expectEqual(&engine_context.mEditorWorld, escape.World);
    try std.testing.expect(ui_manager.KeyTakerFor(.A) == null);

    //typing into the menu's field: it has the keyboard, and it is in the popup's scene, so it goes first
    try world.Press(world.mField);
    try std.testing.expectEqual(.Focus, ui_manager.KeyTakerFor(.ESCAPE).?.Kind);
    try std.testing.expectEqual(.Focus, ui_manager.KeyTakerFor(.A).?.Kind);
    try std.testing.expectEqual(&engine_context.mEditorWorld, ui_manager.KeyTakerFor(.A).?.World);

    //Escape ends the edit first, then the next one closes the menu
    try ui_manager.OnKeyTaken(engine_context, ui_manager.KeyTakerFor(.ESCAPE).?, .{ ._InputCode = .ESCAPE, ._Repeat = 0 });
    try std.testing.expect(ui_manager.mFocusSystem.Focused() == null);
    try std.testing.expect(ui_manager.mPopupSystem.IsOpen(world.mMenu));
    try ui_manager.OnKeyTaken(engine_context, ui_manager.KeyTakerFor(.ESCAPE).?, .{ ._InputCode = .ESCAPE, ._Repeat = 0 });
    try std.testing.expect(!ui_manager.mPopupSystem.IsOpen(world.mMenu));
}
