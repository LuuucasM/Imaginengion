//! The pointer system on real entities: given what is under the pointer, which entities get HoveredTag and
//! PressedTag, and which events are sent to which. No window needed: finding what is under the mouse is the
//! caller's job (a ray cast), so the tests just say what it is. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const UIEvent = @import("../../Events/UIEventData.zig").EventT;
const Vec3 = @import("../../Math/MathTypes.zig").Vec3;

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const HoveredTag = EntityComponents.HoveredTag;
const PressedTag = EntityComponents.PressedTag;

const SEventData = @import("../../Events/SManagerData.zig");
const EEventData = @import("../../Events/EManagerData.zig");
const ECSEventData = @import("../../Events/ECSEventData.zig");

const NOWHERE = Vec3(f32){ .x = 0, .y = 0, .z = 0 };

/// A menu with a Play button that has a label on it, and a Quit button beside it
const TestWorld = struct {
    mEngineContext: *EngineContext,
    mMenu: Entity = .uninit,
    mPlay: Entity = .uninit,
    mLabel: Entity = .uninit,
    mQuit: Entity = .uninit,

    fn Init() !*TestWorld {
        const self = try std.heap.page_allocator.create(TestWorld);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        try engine_context.mEditorWorld.Init(engine_context.EngineAllocator());

        const scene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
        self.mMenu = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
        self.mPlay = try self.mMenu.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
        self.mLabel = try self.mPlay.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
        self.mQuit = try self.mMenu.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        engine_context.mPointerSystem.Deinit(engine_context.EngineAllocator());
        engine_context.mUIEventManager.Deinit(engine_context.EngineAllocator());
        engine_context.mEditorWorld.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    fn Hover(self: *TestWorld, target: ?Entity) !void {
        try self.mEngineContext.mPointerSystem.UpdateHover(self.mEngineContext, target, NOWHERE);
    }

    /// The events sent since the last call, the way the frame's processing empties them
    fn TakeEvents(self: *TestWorld) ![]UIEvent {
        const engine_context = self.mEngineContext;
        const queued = engine_context.mUIEventManager.mEventsArray.getPtr(.Pointer);
        const taken = try engine_context.FrameAllocator().dupe(UIEvent, queued.items);
        queued.clearRetainingCapacity();
        return taken;
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

const Kind = std.meta.Tag(UIEvent);

/// Who an event is for
fn EntityOf(event: UIEvent) Entity {
    return switch (event) {
        .Default => unreachable,
        inline else => |e| e.mEntity,
    };
}

/// Exactly these entities got an event of this kind, in any order
fn ExpectSent(events: []const UIEvent, kind: Kind, expected: []const Entity) !void {
    var count: usize = 0;
    for (events) |event| {
        if (std.meta.activeTag(event) != kind) continue;
        count += 1;
        var found = false;
        for (expected) |entity| found = found or entity.mID == EntityOf(event).mID;
        try std.testing.expect(found);
    }
    try std.testing.expectEqual(expected.len, count);
}

fn ExpectTagged(comptime tag: type, tagged: []const Entity, untagged: []const Entity) !void {
    for (tagged) |entity| try std.testing.expect(entity.HasComponent(tag));
    for (untagged) |entity| try std.testing.expect(!entity.HasComponent(tag));
}

test "the entity under the pointer and everything it is inside are hovered, and hear it enter and leave" {
    const world = try TestWorld.Init();
    defer world.Deinit();

    try world.Hover(world.mLabel);
    try ExpectTagged(HoveredTag, &.{ world.mLabel, world.mPlay, world.mMenu }, &.{world.mQuit});
    try ExpectSent(try world.TakeEvents(), .PointerEnter, &.{ world.mLabel, world.mPlay, world.mMenu });

    //a frame with the pointer still there is nothing new
    try world.Hover(world.mLabel);
    try std.testing.expectEqual(@as(usize, 0), (try world.TakeEvents()).len);

    //across to the other button: still inside the menu, which hears nothing
    try world.Hover(world.mQuit);
    try ExpectTagged(HoveredTag, &.{ world.mQuit, world.mMenu }, &.{ world.mLabel, world.mPlay });
    var events = try world.TakeEvents();
    try ExpectSent(events, .PointerExit, &.{ world.mLabel, world.mPlay });
    try ExpectSent(events, .PointerEnter, &.{world.mQuit});

    //off everything
    try world.Hover(null);
    try ExpectTagged(HoveredTag, &.{}, &.{ world.mLabel, world.mPlay, world.mQuit, world.mMenu });
    events = try world.TakeEvents();
    try ExpectSent(events, .PointerExit, &.{ world.mQuit, world.mMenu });
}

test "a click in place clicks the whole chain, with how many times and what was actually under the pointer" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const pointer = &engine_context.mPointerSystem;
    const chain = [_]Entity{ world.mLabel, world.mPlay, world.mMenu };

    try world.Hover(world.mLabel);
    _ = try world.TakeEvents();

    try pointer.OnPressed(engine_context, .BUTTON_LEFT);
    try ExpectTagged(PressedTag, &chain, &.{world.mQuit});
    try ExpectSent(try world.TakeEvents(), .PointerPressed, &chain);

    try pointer.OnReleased(engine_context, .BUTTON_LEFT);
    try ExpectTagged(PressedTag, &.{}, &chain);
    try ExpectSent(try world.TakeEvents(), .PointerReleased, &chain);

    try pointer.OnClicked(engine_context, .BUTTON_LEFT, 2);
    const events = try world.TakeEvents();
    try ExpectSent(events, .PointerClicked, &chain);
    for (events) |event| {
        try std.testing.expectEqual(@as(u8, 2), event.PointerClicked.mClicks);
        try std.testing.expectEqual(world.mLabel.mID, event.PointerClicked.mTarget.mID);
    }
}

test "a release goes to what was pressed, and a click only to what was under the pointer at both ends" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const pointer = &engine_context.mPointerSystem;
    const pressed_chain = [_]Entity{ world.mLabel, world.mPlay, world.mMenu };

    //down on the Play button's label, then across to Quit before letting go
    try world.Hover(world.mLabel);
    try pointer.OnPressed(engine_context, .BUTTON_LEFT);
    try world.Hover(world.mQuit);
    //still held though the pointer has left it
    try ExpectTagged(PressedTag, &pressed_chain, &.{world.mQuit});
    _ = try world.TakeEvents();

    try pointer.OnReleased(engine_context, .BUTTON_LEFT);
    try ExpectTagged(PressedTag, &.{}, &pressed_chain);
    try ExpectSent(try world.TakeEvents(), .PointerReleased, &pressed_chain);

    //neither button was under the pointer both times. The menu was
    try pointer.OnClicked(engine_context, .BUTTON_LEFT, 1);
    const events = try world.TakeEvents();
    try ExpectSent(events, .PointerClicked, &.{world.mMenu});
    try std.testing.expectEqual(world.mQuit.mID, events[0].PointerClicked.mTarget.mID);
}

test "an entity held by two buttons stays pressed until both are up" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const pointer = &engine_context.mPointerSystem;

    try world.Hover(world.mQuit);
    try pointer.OnPressed(engine_context, .BUTTON_LEFT);
    try pointer.OnPressed(engine_context, .BUTTON_RIGHT);

    try pointer.OnReleased(engine_context, .BUTTON_LEFT);
    try std.testing.expect(world.mQuit.HasComponent(PressedTag));
    try pointer.OnReleased(engine_context, .BUTTON_RIGHT);
    try std.testing.expect(!world.mQuit.HasComponent(PressedTag));
}

test "when the hovered entity is deleted, what it was inside still hears the pointer leave" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    try world.Hover(world.mLabel);
    _ = try world.TakeEvents();

    try world.mLabel.Delete(engine_context);
    try world.EndFrame();

    try world.Hover(null);
    try ExpectTagged(HoveredTag, &.{}, &.{ world.mPlay, world.mMenu });
    try ExpectSent(try world.TakeEvents(), .PointerExit, &.{ world.mPlay, world.mMenu });
}
