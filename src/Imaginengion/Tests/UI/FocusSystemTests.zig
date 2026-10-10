//! The focus system on real entities: which text input has the keyboard, what typing does to its text, how an edit
//! ends, and the events and caret that go with it. No window or font needed: presses come through the pointer system
//! the way the editor hands them over, and text without a font puts the caret at the start of its line. Run with
//! `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const UIEventData = @import("../../Events/UIEventData.zig");
const EntityUIEvent = UIEventData.EntityEvent;
const MouseCodes = @import("../../Inputs/InputEnums.zig").MouseCodes;
const ScanCodes = @import("../../Inputs/InputEnums.zig").ScanCodes;

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const FocusedTag = EntityComponents.FocusedTag;
const TextInputComponent = @import("../../ECSComponents/UIComponents.zig").TextInputComponent;
const UIElementComponent = EntityComponents.UIElementComponent;
const UIManager = @import("../../UI/UIManager.zig");
const TextComponent = EntityComponents.TextComponent;
const ShapeComponent = EntityComponents.ShapeComponent;
const SurfaceComponent = EntityComponents.SurfaceComponent;
const LayoutDirtyTag = EntityComponents.LayoutDirtyTag;
const EntityChildComponent = @import("../../ECS/Components.zig").ChildComponent(Entity.Type);
const StackPosComponent = @import("../../ECSComponents/SComponents.zig").StackPosComponent;

const SEventData = @import("../../Events/SManagerData.zig");
const EEventData = @import("../../Events/EManagerData.zig");
const ECSEventData = @import("../../Events/ECSEventData.zig");

/// A form with a Name field and a Team field in it, and an OK button beside them
const TestWorld = struct {
    mEngineContext: *EngineContext,
    mForm: Entity = .uninit,
    mName: Entity = .uninit,
    mTeam: Entity = .uninit,
    mOK: Entity = .uninit,

    fn Init() !*TestWorld {
        const self = try std.heap.page_allocator.create(TestWorld);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        try engine_context.mUIManager.Init(engine_context.EngineAllocator());
        try engine_context.mEditorWorld.Init(engine_context.EngineAllocator());

        const scene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
        self.mForm = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
        self.mName = try self.TextInput("Bob");
        self.mTeam = try self.TextInput("Red");
        self.mOK = try self.mForm.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
        _ = try self.TakeEvents();
        return self;
    }

    fn TextInput(self: *TestWorld, text: []const u8) !Entity {
        const engine_context = self.mEngineContext;
        const entity = try self.mForm.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
        const text_component = try entity.AddComponent(engine_context, TextComponent{});
        try text_component.SetText(engine_context, text);
        _ = try entity.AddComponent(engine_context, SurfaceComponent{});
        try AddUI(engine_context, entity, TextInputComponent{});
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

    /// A button going down over `target`, handed to the pointer system and then the focus system like the editor does
    fn Press(self: *TestWorld, target: ?Entity, button: MouseCodes) !void {
        const engine_context = self.mEngineContext;
        try engine_context.mPointerSystem.Update(engine_context, .{ .Target = target });
        try engine_context.mPointerSystem.OnPressed(engine_context, button);
        try engine_context.mUIManager.mFocusSystem.OnPressed(engine_context, &engine_context.mPointerSystem, button);
        try engine_context.mPointerSystem.OnReleased(engine_context, button);
    }

    fn Key(self: *TestWorld, key: ScanCodes) !void {
        try self.mEngineContext.mUIManager.mFocusSystem.OnKeyPressed(self.mEngineContext, .{ ._InputCode = key, ._Repeat = 0 });
    }

    fn Type(self: *TestWorld, text: []const u8) !void {
        try self.mEngineContext.mUIManager.mFocusSystem.OnTextTyped(self.mEngineContext, text);
    }

    fn TextOf(entity: Entity) []const u8 {
        return entity.GetComponent(TextComponent).?.mText.items;
    }

    /// The focus and text events sent since the last call, the way the frame's processing empties them. Pointer
    /// events are left out: they are the pointer system's tests'
    fn TakeEvents(self: *TestWorld) ![]EntityUIEvent {
        const engine_context = self.mEngineContext;
        const queued = engine_context.mUIManager.mEventManager.mEventsArray.getPtr(.UI);
        var taken: std.ArrayList(EntityUIEvent) = .empty;
        for (queued.items) |event| {
            const entity_event = switch (event) {
                .Entity => |e| e,
                else => continue,
            };
            switch (entity_event.mEvent) {
                .FocusGained, .FocusLost, .TextChanged, .TextSubmitted => try taken.append(engine_context.FrameAllocator(), entity_event),
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

const Kind = std.meta.Tag(UIEventData.UIEvent);

/// The kinds of events in order, one for each entity in the text input's chain (it, then the form)
fn ExpectKinds(events: []const EntityUIEvent, kinds: []const Kind) !void {
    try std.testing.expectEqual(kinds.len * 2, events.len);
    for (kinds, 0..) |kind, i| {
        try std.testing.expectEqual(kind, std.meta.activeTag(events[i * 2].mEvent));
        try std.testing.expectEqual(kind, std.meta.activeTag(events[i * 2 + 1].mEvent));
    }
}

fn ExpectFocused(world: *TestWorld, expected: ?Entity) !void {
    const focused = world.mEngineContext.mUIManager.mFocusSystem.Focused();
    try std.testing.expectEqual(expected == null, focused == null);
    if (expected) |entity| try std.testing.expectEqual(entity.mID, focused.?.mID);
    for ([_]Entity{ world.mName, world.mTeam }) |text_input| {
        const is_it = expected != null and expected.?.mID == text_input.mID;
        try std.testing.expectEqual(is_it, text_input.HasComponent(FocusedTag));
    }
    try std.testing.expectEqual(expected != null, world.mEngineContext.mInputManager.mKeyboardTaken);
}

test "pressing a text input gives it the keyboard, with the caret at the end, and tells it and its parents" {
    const world = try TestWorld.Init();
    defer world.Deinit();

    try world.Press(world.mName, .BUTTON_LEFT);
    try ExpectFocused(world, world.mName);
    try std.testing.expectEqual(@as(usize, 3), world.mEngineContext.mUIManager.mFocusSystem.Caret());

    const events = try world.TakeEvents();
    try ExpectKinds(events, &.{.FocusGained});
    try std.testing.expectEqual(world.mName.mID, events[0].mEntity.mID);
    try std.testing.expectEqual(world.mForm.mID, events[1].mEntity.mID);
    try std.testing.expectEqual(world.mName.mID, events[1].mEvent.FocusGained.mTarget.mID);

    //the game's polled keys read nothing while it is being typed into
    try std.testing.expect(!world.mEngineContext.mInputManager.IsKeyPressed(.A));

    //pressing something that isn't a text input gives nothing the keyboard
    try world.Press(world.mOK, .BUTTON_LEFT);
    try ExpectFocused(world, null);
    try world.Press(world.mForm, .BUTTON_LEFT);
    try ExpectFocused(world, null);
}

test "pressing the box a text input sits in gives it the keyboard, unless the box holds more than one" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    //a text field: a box holding just its text, which can be empty and so have nothing to press
    const field = try world.mForm.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    const shown = try field.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    _ = try shown.AddComponent(engine_context, TextComponent{});
    _ = try shown.AddComponent(engine_context, SurfaceComponent{});
    try AddUI(engine_context, shown, TextInputComponent{});

    try world.Press(field, .BUTTON_LEFT);
    const focus = &engine_context.mUIManager.mFocusSystem;
    try std.testing.expectEqual(shown.mID, focus.Focused().?.mID);
    try world.Type("hi");
    try std.testing.expectEqualStrings("hi", TestWorld.TextOf(shown));

    //pressing the box again keeps the edit going
    try world.Press(field, .BUTTON_LEFT);
    try std.testing.expectEqual(shown.mID, focus.Focused().?.mID);

    //the form holds two: a press on it is on neither, and ends the edit
    try world.Press(world.mForm, .BUTTON_LEFT);
    try ExpectFocused(world, null);
}

test "typing goes in at the caret, and the keys move it and delete around it" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const focus = &world.mEngineContext.mUIManager.mFocusSystem;

    try world.Press(world.mName, .BUTTON_LEFT);
    _ = try world.TakeEvents();
    try world.mName.ClearLayoutDirty(world.mEngineContext);

    try world.Type("by");
    try std.testing.expectEqualStrings("Bobby", TestWorld.TextOf(world.mName));
    try ExpectKinds(try world.TakeEvents(), &.{.TextChanged});
    //layout sizes text to fit it
    try std.testing.expect(world.mName.HasComponent(LayoutDirtyTag));

    try world.Key(.LEFT);
    try world.Key(.LEFT);
    try world.Key(.BACKSPACE);
    try std.testing.expectEqualStrings("Boby", TestWorld.TextOf(world.mName));
    try std.testing.expectEqual(@as(usize, 2), focus.Caret());

    try world.Key(.HOME);
    try world.Key(.DELETE);
    try world.Type("R");
    try std.testing.expectEqualStrings("Roby", TestWorld.TextOf(world.mName));

    try world.Key(.END);
    try world.Key(.RIGHT);
    try std.testing.expectEqual(@as(usize, 4), focus.Caret());
    //nothing to delete past the end: no change, no event
    _ = try world.TakeEvents();
    try world.Key(.DELETE);
    try std.testing.expectEqual(@as(usize, 0), (try world.TakeEvents()).len);

    //a pasted or typed line break never makes it in
    try world.Type("\n");
    try std.testing.expectEqualStrings("Roby", TestWorld.TextOf(world.mName));
}

test "a text input that focuses on a double click ignores a single press, and takes the keyboard on a double click" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    UIManager.GetUIComponent(world.mName, TextInputComponent).?.mFocusOn = .DoubleClick;

    try world.Press(world.mName, .BUTTON_LEFT);
    try ExpectFocused(world, null);

    //a double click comes as a pointer click to the text input and the form; only the text input's own counts
    for ([_]Entity{ world.mName, world.mForm }) |entity| {
        try engine_context.mUIManager.OnPointerEvent(engine_context, .{ .mEntity = entity, .mEvent = .{ .PointerClicked = .{
            .mButton = .BUTTON_LEFT,
            .mClicks = 2,
            .mPosition = .{ .x = 0, .y = 0, .z = 0 },
            .mTarget = world.mName,
        } } });
    }
    try ExpectFocused(world, world.mName);
    try std.testing.expectEqual(@as(usize, 3), engine_context.mUIManager.mFocusSystem.Caret());

    //once it has the keyboard a press on it stays with it, and a press elsewhere still ends the edit
    try world.Press(world.mName, .BUTTON_LEFT);
    try ExpectFocused(world, world.mName);
    try world.Press(world.mOK, .BUTTON_LEFT);
    try ExpectFocused(world, null);
}

test "Enter keeps the edit and lets go of the keyboard" {
    const world = try TestWorld.Init();
    defer world.Deinit();

    try world.Press(world.mName, .BUTTON_LEFT);
    try world.Type("by");
    _ = try world.TakeEvents();

    try world.Key(.RETURN);
    try ExpectFocused(world, null);
    try std.testing.expectEqualStrings("Bobby", TestWorld.TextOf(world.mName));
    try ExpectKinds(try world.TakeEvents(), &.{ .TextSubmitted, .FocusLost });

    //nothing has the keyboard: typing goes nowhere
    try world.Type("!");
    try std.testing.expectEqualStrings("Bobby", TestWorld.TextOf(world.mName));
}

test "Escape puts back the text it had and lets go, without submitting" {
    const world = try TestWorld.Init();
    defer world.Deinit();

    try world.Press(world.mName, .BUTTON_LEFT);
    try world.Key(.BACKSPACE);
    try world.Type("x");
    _ = try world.TakeEvents();

    try world.Key(.ESCAPE);
    try ExpectFocused(world, null);
    try std.testing.expectEqualStrings("Bob", TestWorld.TextOf(world.mName));
    try ExpectKinds(try world.TakeEvents(), &.{ .TextChanged, .FocusLost });

    //nothing was changed: nothing to put back, so no TextChanged
    try world.Press(world.mName, .BUTTON_LEFT);
    _ = try world.TakeEvents();
    try world.Key(.ESCAPE);
    try ExpectKinds(try world.TakeEvents(), &.{.FocusLost});
}

test "pressing somewhere else keeps the edit, and pressing another text input moves the keyboard to it" {
    const world = try TestWorld.Init();
    defer world.Deinit();

    try world.Press(world.mName, .BUTTON_LEFT);
    try world.Type("by");
    _ = try world.TakeEvents();

    try world.Press(world.mTeam, .BUTTON_LEFT);
    try ExpectFocused(world, world.mTeam);
    try std.testing.expectEqualStrings("Bobby", TestWorld.TextOf(world.mName));
    const events = try world.TakeEvents();
    try ExpectKinds(events, &.{ .TextSubmitted, .FocusLost, .FocusGained });
    try std.testing.expectEqual(world.mName.mID, events[0].mEvent.TextSubmitted.mTarget.mID);
    try std.testing.expectEqual(world.mTeam.mID, events[4].mEvent.FocusGained.mTarget.mID);

    //pressing the one that has it keeps it
    try world.Press(world.mTeam, .BUTTON_LEFT);
    try ExpectFocused(world, world.mTeam);
    try std.testing.expectEqual(@as(usize, 0), (try world.TakeEvents()).len);

    //any button outside lets go, but only the left one gives a text input the keyboard
    try world.Press(world.mName, .BUTTON_RIGHT);
    try ExpectFocused(world, null);
    try world.Press(null, .BUTTON_LEFT);
    try ExpectFocused(world, null);
}

test "the caret is a quad on a child of the text input, there only while it has the keyboard" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const focus = &engine_context.mUIManager.mFocusSystem;

    try world.Press(world.mName, .BUTTON_LEFT);
    try focus.Update(engine_context);
    const caret = focus.mCaretEntity.?;
    try std.testing.expect(caret.HasComponent(ShapeComponent));
    //colored by the theme
    try std.testing.expectEqualStrings("Caret", UIManager.GetUIComponent(caret, @import("../../ECSComponents/UIComponents.zig").StyleComponent).?.mStyle.items);
    try std.testing.expectEqual(world.mName.mID, caret.GetComponent(EntityChildComponent).?.mParent);
    //showing straight away, then blinking off
    try std.testing.expect(caret.GetComponent(SurfaceComponent).?.mShouldRender);
    focus.mBlinkTime = 0.75;
    try focus.Update(engine_context);
    try std.testing.expect(!caret.GetComponent(SurfaceComponent).?.mShouldRender);
    //an edit shows it again
    try world.Type("!");
    try focus.Update(engine_context);
    try std.testing.expect(caret.GetComponent(SurfaceComponent).?.mShouldRender);

    //the same caret every frame
    try focus.Update(engine_context);
    try std.testing.expectEqual(caret.mID, focus.mCaretEntity.?.mID);

    try world.Key(.RETURN);
    try std.testing.expect(focus.mCaretEntity == null);
    //hidden now, gone at the end of the frame
    try std.testing.expect(!caret.GetComponent(SurfaceComponent).?.mShouldRender);
    try world.EndFrame();
    try std.testing.expect(!caret.IsActive());
}

test "a text input deleted while it has the keyboard lets go of it" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    try world.Press(world.mName, .BUTTON_LEFT);
    try engine_context.mUIManager.mFocusSystem.Update(engine_context);
    try world.mName.Delete(engine_context);
    try world.EndFrame();
    _ = try world.TakeEvents();

    try engine_context.mUIManager.mFocusSystem.Update(engine_context);
    try std.testing.expect(engine_context.mUIManager.mFocusSystem.Focused() == null);
    try std.testing.expect(!engine_context.mInputManager.mKeyboardTaken);
    try std.testing.expectEqual(@as(usize, 0), (try world.TakeEvents()).len);
}

test "a text input's turn at the keyboard is its scene's place in the stack" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const focus = &engine_context.mUIManager.mFocusSystem;

    try std.testing.expect(focus.FocusedStackPos() == null);
    try world.Press(world.mName, .BUTTON_LEFT);
    const scene = world.mName.GetComponent(EntityComponents.EntitySceneComponent).?.mScene;
    try std.testing.expectEqual(scene.GetComponent(StackPosComponent).?.mPosition, focus.FocusedStackPos().?);
}
