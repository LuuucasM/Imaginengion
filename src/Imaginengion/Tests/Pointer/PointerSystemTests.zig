//! The pointer system on real entities: given what is under the pointer, which entities get HoveredTag and
//! PressedTag, and which events are sent to which. No window needed: finding what is under the mouse is the
//! caller's job (a ray cast), so the tests just say what it is. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const PointerEvent = @import("../../Events/PointerEventData.zig").EventT;
const Vec3 = @import("../../Math/MathTypes.zig").Vec3;
const Vec2 = @import("../../Math/MathTypes.zig").Vec2;
const CameraRay = @import("../../Math/CameraRay.zig");
const PointerSystem = @import("../../Pointer/PointerSystem.zig");

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const HoveredTag = EntityComponents.HoveredTag;
const PressedTag = EntityComponents.PressedTag;
const DropHoverTag = EntityComponents.DropHoverTag;
const DisabledTag = EntityComponents.DisabledTag;
const DragSourceComponent = EntityComponents.DragSourceComponent;
const DropTargetComponent = EntityComponents.DropTargetComponent;
const QuadComponent = EntityComponents.QuadComponent;
const TextComponent = EntityComponents.TextComponent;

const SEventData = @import("../../Events/SManagerData.zig");
const EEventData = @import("../../Events/EManagerData.zig");
const ECSEventData = @import("../../Events/ECSEventData.zig");

const NOWHERE = Vec3(f32){ .x = 0, .y = 0, .z = 0 };
const FOV: f32 = std.math.degreesToRadians(@as(f32, 60.0));
const eps: f32 = 0.01;

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
        engine_context.mPointerEventManager.Deinit(engine_context.EngineAllocator());
        engine_context.mEditorWorld.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    fn Hover(self: *TestWorld, target: ?Entity) !void {
        try self.mEngineContext.mPointerSystem.Update(self.mEngineContext, .{ .Target = target });
    }

    /// The mouse at `pixel` of a width x height view whose camera sits at the origin looking down -z, over `target`
    fn MoveTo(self: *TestWorld, target: ?Entity, pixel: Vec2(f32), width: f32, height: f32) !void {
        try self.mEngineContext.mPointerSystem.Update(self.mEngineContext, .{ .Target = target, .Pixel = pixel, .View = ViewThrough(pixel, width, height) });
    }

    /// The events sent since the last call, the way the frame's processing empties them
    fn TakeEvents(self: *TestWorld) ![]PointerEvent {
        const engine_context = self.mEngineContext;
        const queued = engine_context.mPointerEventManager.mEventsArray.getPtr(.Pointer);
        const taken = try engine_context.FrameAllocator().dupe(PointerEvent, queued.items);
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

/// The pointer's ray through `pixel` of a width x height view whose camera sits at the origin looking down -z
fn ViewThrough(pixel: Vec2(f32), width: f32, height: f32) PointerSystem.View {
    const pose = CameraRay.Pose{ .Position = NOWHERE, .Rotation = .{ .w = 1, .x = 0, .y = 0, .z = 0 } };
    return .{
        .Ray = CameraRay.MakeRay(pose, CameraRay.ComputeRayParams(FOV, width, height), pixel),
        .CameraView = .{ .Pose = pose, .TanHalfFov = @tan(FOV / 2), .TargetWidth = width, .TargetHeight = height, .FarDistance = 1000, .DisplayScale = 1 },
    };
}

const Kind = std.meta.Tag(PointerEvent);

/// Who an event is for
fn EntityOf(event: PointerEvent) Entity {
    return switch (event) {
        .Default => unreachable,
        inline else => |e| e.mEntity,
    };
}

/// Exactly these entities got an event of this kind, in any order
fn ExpectSent(events: []const PointerEvent, kind: Kind, expected: []const Entity) !void {
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

test "a disabled entity and what is inside it are passed by: the pointer is over what it is inside instead" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const pointer = &engine_context.mPointerSystem;
    _ = try world.mPlay.AddComponent(engine_context, DisabledTag{});

    try world.Hover(world.mLabel);
    try ExpectTagged(HoveredTag, &.{world.mMenu}, &.{ world.mLabel, world.mPlay });
    try ExpectSent(try world.TakeEvents(), .PointerEnter, &.{world.mMenu});
    try std.testing.expect(PointerSystem.IsDisabled(world.mLabel));
    try std.testing.expect(!PointerSystem.IsDisabled(world.mQuit));

    //a click on it clicks only the menu, with the menu as what was clicked
    try pointer.OnPressed(engine_context, .BUTTON_LEFT);
    try pointer.OnReleased(engine_context, .BUTTON_LEFT);
    try pointer.OnClicked(engine_context, .BUTTON_LEFT, 1);
    const events = try world.TakeEvents();
    try ExpectSent(events, .PointerClicked, &.{world.mMenu});
    try ExpectTagged(PressedTag, &.{}, &.{ world.mLabel, world.mPlay, world.mMenu });
    for (events) |event| {
        if (event == .PointerClicked) try std.testing.expectEqual(world.mMenu.mID, event.PointerClicked.mTarget.mID);
    }

    //enabled again, the next frame it is hovered like anything else
    try world.mPlay.RemoveComponentSync(engine_context, DisabledTag);
    try world.Hover(world.mLabel);
    try ExpectTagged(HoveredTag, &.{ world.mLabel, world.mPlay, world.mMenu }, &.{});
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

//-------------------------------dragging-------------------------------

/// The one event of this kind that is for `entity`
fn EventFor(events: []const PointerEvent, kind: Kind, entity: Entity) !PointerEvent {
    for (events) |event| {
        if (std.meta.activeTag(event) == kind and EntityOf(event).mID == entity.mID) return event;
    }
    return error.TestExpectedEvent;
}

fn ExpectVec3(x: f32, y: f32, z: f32, actual: Vec3(f32)) !void {
    try std.testing.expectApproxEqAbs(x, actual.x, eps);
    try std.testing.expectApproxEqAbs(y, actual.y, eps);
    try std.testing.expectApproxEqAbs(z, actual.z, eps);
}

test "a press that barely moves is still a click, and no drag" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const pointer = &engine_context.mPointerSystem;

    try world.MoveTo(world.mQuit, .{ .x = 960, .y = 540 }, 1920, 1080);
    try pointer.OnPressed(engine_context, .BUTTON_LEFT);
    //3 pixels: under the 4 that make it a drag
    try world.MoveTo(world.mQuit, .{ .x = 963, .y = 540 }, 1920, 1080);
    try pointer.OnReleased(engine_context, .BUTTON_LEFT);
    try pointer.OnClicked(engine_context, .BUTTON_LEFT, 1);

    const events = try world.TakeEvents();
    try ExpectSent(events, .PointerDragStart, &.{});
    try ExpectSent(events, .PointerDrag, &.{});
    try ExpectSent(events, .PointerDragEnd, &.{});
    try ExpectSent(events, .PointerClicked, &.{ world.mQuit, world.mMenu });
}

test "a drag on an overlay is in canvas units, goes to the whole chain, and is never a click as well" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const pointer = &engine_context.mPointerSystem;
    const chain = [_]Entity{ world.mLabel, world.mPlay, world.mMenu };

    //scale with screen at 1080p is one canvas unit per pixel
    try world.MoveTo(world.mLabel, .{ .x = 960, .y = 540 }, 1920, 1080);
    try pointer.OnPressed(engine_context, .BUTTON_LEFT);
    _ = try world.TakeEvents();

    //30 right and 20 down the screen, which is 20 down the canvas: its y runs up
    try world.MoveTo(world.mLabel, .{ .x = 990, .y = 560 }, 1920, 1080);
    var events = try world.TakeEvents();
    try ExpectSent(events, .PointerDragStart, &chain);
    try ExpectSent(events, .PointerDrag, &chain);
    var drag = (try EventFor(events, .PointerDrag, world.mPlay)).PointerDrag;
    try ExpectVec3(30, -20, 0, drag.mDelta);
    try ExpectVec3(30, -20, 0, drag.mTotal);
    try std.testing.expectEqual(world.mLabel.mID, drag.mTarget.mID);

    //on across the Quit button and off everything: what is held still hears it, from wherever the pointer is
    try world.MoveTo(null, .{ .x = 1000, .y = 560 }, 1920, 1080);
    events = try world.TakeEvents();
    try ExpectSent(events, .PointerDragStart, &.{});
    drag = (try EventFor(events, .PointerDrag, world.mPlay)).PointerDrag;
    try ExpectVec3(10, 0, 0, drag.mDelta);
    try ExpectVec3(40, -20, 0, drag.mTotal);

    //a frame without moving is no event
    try world.MoveTo(null, .{ .x = 1000, .y = 560 }, 1920, 1080);
    try ExpectSent(try world.TakeEvents(), .PointerDrag, &.{});

    //back to where it started and let go: the input manager would call that a click, but it was a drag
    try world.MoveTo(world.mLabel, .{ .x = 960, .y = 540 }, 1920, 1080);
    _ = try world.TakeEvents();
    try pointer.OnReleased(engine_context, .BUTTON_LEFT);
    try pointer.OnClicked(engine_context, .BUTTON_LEFT, 1);
    events = try world.TakeEvents();
    try ExpectSent(events, .PointerDragEnd, &chain);
    try ExpectVec3(0, 0, 0, (try EventFor(events, .PointerDragEnd, world.mPlay)).PointerDragEnd.mTotal);
    try ExpectSent(events, .PointerClicked, &.{});
}

test "the same drag across the screen is the same drag in canvas units at any resolution" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const pointer = &engine_context.mPointerSystem;

    //a third of the way across a 720p view, which is 1.5 canvas units per pixel under scale with screen
    try world.MoveTo(world.mQuit, .{ .x = 640, .y = 360 }, 1280, 720);
    try pointer.OnPressed(engine_context, .BUTTON_LEFT);
    try world.MoveTo(world.mQuit, .{ .x = 660, .y = 360 }, 1280, 720);

    const drag = (try EventFor(try world.TakeEvents(), .PointerDrag, world.mQuit)).PointerDrag;
    try ExpectVec3(30, 0, 0, drag.mDelta);
}

test "a drag waits while there is no view to follow the pointer through, then carries on" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const pointer = &engine_context.mPointerSystem;

    try world.MoveTo(world.mQuit, .{ .x = 960, .y = 540 }, 1920, 1080);
    try pointer.OnPressed(engine_context, .BUTTON_LEFT);
    try world.MoveTo(world.mQuit, .{ .x = 970, .y = 540 }, 1920, 1080);
    _ = try world.TakeEvents();

    //the mouse has moved, but with no view there is nothing to measure it across
    try pointer.Update(engine_context, .{ .Pixel = .{ .x = 5000, .y = 5000 } });
    try ExpectSent(try world.TakeEvents(), .PointerDrag, &.{});

    try world.MoveTo(null, .{ .x = 1000, .y = 540 }, 1920, 1080);
    const drag = (try EventFor(try world.TakeEvents(), .PointerDrag, world.mQuit)).PointerDrag;
    try ExpectVec3(30, 0, 0, drag.mDelta);
    try ExpectVec3(40, 0, 0, drag.mTotal);
}

test "a drag on something in the world is in world units, across a plane facing the camera where it was grabbed" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const pointer = &engine_context.mPointerSystem;

    const level = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const crate = try level.CreateEntity(engine_context, Entity.DefaultConfig);

    //grabbed 10 in front of the camera, where a pixel of a 1080 tall, 60 degree view covers 2 * 10 * tan(30) / 1080
    const grab_pixel = Vec2(f32){ .x = 960, .y = 540 };
    try pointer.Update(engine_context, .{ .Target = crate, .Position = .{ .x = 0, .y = 0, .z = -10 }, .Pixel = grab_pixel, .View = ViewThrough(grab_pixel, 1920, 1080) });
    try pointer.OnPressed(engine_context, .BUTTON_LEFT);
    try world.MoveTo(crate, .{ .x = 1060, .y = 540 }, 1920, 1080);

    const per_pixel = 2.0 * 10.0 * @tan(FOV / 2) / 1080.0;
    const drag = (try EventFor(try world.TakeEvents(), .PointerDrag, crate)).PointerDrag;
    try ExpectVec3(100 * per_pixel, 0, 0, drag.mDelta);
}

//-----------------------------drag and drop-----------------------------

/// The Play button can be picked up, and what it carries is its quad: it stands in for whatever a real source would
/// carry. Pressed on its label, then dragged 40 pixels to the right over `over`
fn PickUpPlay(world: *TestWorld, over: ?Entity) !void {
    const engine_context = world.mEngineContext;
    _ = try world.mPlay.AddComponent(engine_context, DragSourceComponent{});
    _ = try world.mPlay.AddComponent(engine_context, QuadComponent{});
    try world.MoveTo(world.mLabel, .{ .x = 960, .y = 540 }, 1920, 1080);
    try engine_context.mPointerSystem.OnPressed(engine_context, .BUTTON_LEFT);
    try world.MoveTo(over, .{ .x = 1000, .y = 540 }, 1920, 1080);
    _ = try world.TakeEvents();
}

test "a drag source held over a target that takes it lights it up, and letting go drops it there" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const pointer = &engine_context.mPointerSystem;
    _ = try world.mQuit.AddComponent(engine_context, DropTargetComponent.Accepting(&.{QuadComponent}));

    try PickUpPlay(world, world.mQuit);
    try std.testing.expectEqual(world.mPlay.mID, pointer.Carrying().?.mID);
    try std.testing.expect(world.mQuit.HasComponent(DropHoverTag));

    try pointer.OnReleased(engine_context, .BUTTON_LEFT);
    const events = try world.TakeEvents();
    try ExpectSent(events, .PointerDropped, &.{world.mQuit});
    try std.testing.expectEqual(world.mPlay.mID, (try EventFor(events, .PointerDropped, world.mQuit)).PointerDropped.mSource.mID);
    try std.testing.expect(!world.mQuit.HasComponent(DropHoverTag));
    try std.testing.expect(pointer.Carrying() == null);
}

test "a target that takes something else stays dark and gets no drop" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    _ = try world.mQuit.AddComponent(engine_context, DropTargetComponent.Accepting(&.{TextComponent}));

    try PickUpPlay(world, world.mQuit);
    try std.testing.expect(!world.mQuit.HasComponent(DropHoverTag));
    try engine_context.mPointerSystem.OnReleased(engine_context, .BUTTON_LEFT);
    try ExpectSent(try world.TakeEvents(), .PointerDropped, &.{});
}

test "the nearest target that takes it wins, going up from what is under the pointer" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    //the Quit button takes it, and so does the menu it is in
    _ = try world.mQuit.AddComponent(engine_context, DropTargetComponent.Accepting(&.{QuadComponent}));
    _ = try world.mMenu.AddComponent(engine_context, DropTargetComponent.Accepting(&.{QuadComponent}));

    try PickUpPlay(world, world.mQuit);
    try std.testing.expect(world.mQuit.HasComponent(DropHoverTag));
    try std.testing.expect(!world.mMenu.HasComponent(DropHoverTag));

    //over the menu itself: the light moves to it
    try world.MoveTo(world.mMenu, .{ .x = 1010, .y = 540 }, 1920, 1080);
    try std.testing.expect(!world.mQuit.HasComponent(DropHoverTag));
    try std.testing.expect(world.mMenu.HasComponent(DropHoverTag));
}

test "only a drag that starts on a source carries anything, and only with the left button" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const pointer = &engine_context.mPointerSystem;
    _ = try world.mMenu.AddComponent(engine_context, DropTargetComponent.Accepting(&.{QuadComponent}));
    _ = try world.mQuit.AddComponent(engine_context, QuadComponent{});

    //the Quit button has what the menu takes, but it isn't a drag source
    try world.MoveTo(world.mQuit, .{ .x = 960, .y = 540 }, 1920, 1080);
    try pointer.OnPressed(engine_context, .BUTTON_LEFT);
    try world.MoveTo(world.mMenu, .{ .x = 1000, .y = 540 }, 1920, 1080);
    try std.testing.expect(pointer.Carrying() == null);
    try pointer.OnReleased(engine_context, .BUTTON_LEFT);
    try ExpectSent(try world.TakeEvents(), .PointerDropped, &.{});

    //a source dragged with the right button is a plain drag
    _ = try world.mQuit.AddComponent(engine_context, DragSourceComponent{});
    try world.MoveTo(world.mQuit, .{ .x = 960, .y = 540 }, 1920, 1080);
    try pointer.OnPressed(engine_context, .BUTTON_RIGHT);
    try world.MoveTo(world.mMenu, .{ .x = 1000, .y = 540 }, 1920, 1080);
    try std.testing.expect(pointer.Carrying() == null);
    try std.testing.expect(!world.mMenu.HasComponent(DropHoverTag));
}

test "a source deleted mid drag drops nothing" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    _ = try world.mQuit.AddComponent(engine_context, DropTargetComponent.Accepting(&.{QuadComponent}));

    try PickUpPlay(world, world.mQuit);
    try world.mPlay.Delete(engine_context);
    try world.EndFrame();
    try world.MoveTo(world.mQuit, .{ .x = 1010, .y = 540 }, 1920, 1080);
    try std.testing.expect(!world.mQuit.HasComponent(DropHoverTag));

    try engine_context.mPointerSystem.OnReleased(engine_context, .BUTTON_LEFT);
    try ExpectSent(try world.TakeEvents(), .PointerDropped, &.{});
}
