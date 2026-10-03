//! Which pointer and UI events reach entities' event scripts (ScriptsProcessor.EventScripts): a script handing back
//! .Handled keeps what happened from the rest of its chain, the entity's parents, but not an enter or exit, which is
//! each entity's own. No compiled scripts needed: the decision is tested on its own, with what a script would hand back.
//! Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const ScriptsProcessor = @import("../../Scripts/ScriptsProcessor.zig");
const EventScripts = ScriptsProcessor.EventScripts;
const PointerEvent = @import("../../Events/PointerEventData.zig").EventT;
const UIEvent = @import("../../Events/UIEventData.zig").EventT;

/// A panel with a button in it, the button's label in that, and a second button
const TestWorld = struct {
    mEngineContext: *EngineContext,
    mPanel: Entity = .uninit,
    mButton: Entity = .uninit,
    mLabel: Entity = .uninit,
    mOther: Entity = .uninit,

    fn Init() !*TestWorld {
        const self = try std.heap.page_allocator.create(TestWorld);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        try engine_context.mEditorWorld.Init(engine_context.EngineAllocator());
        const scene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
        self.mPanel = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
        self.mButton = try self.mPanel.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
        self.mLabel = try self.mButton.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
        self.mOther = try self.mPanel.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        engine_context.mEditorWorld.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }
};

fn Click(entity: Entity, target: Entity, button: @import("../../Inputs/InputEnums.zig").MouseCodes) PointerEvent {
    return .{ .PointerClicked = .{ .mEntity = entity, .mButton = button, .mClicks = 1, .mPosition = .{ .x = 0, .y = 0, .z = 0 }, .mTarget = target } };
}

test "a script handling a click keeps it from the parents, and only that click" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    var scripts: EventScripts = .{};

    //the label was clicked: the label, the button and the panel each get the click, in that order
    try std.testing.expect(scripts.ShouldRun(Click(world.mLabel, world.mLabel, .BUTTON_LEFT)));
    scripts.After(Click(world.mLabel, world.mLabel, .BUTTON_LEFT), .Continue);
    try std.testing.expect(scripts.ShouldRun(Click(world.mButton, world.mLabel, .BUTTON_LEFT)));
    //the button's script handles it
    scripts.After(Click(world.mButton, world.mLabel, .BUTTON_LEFT), .Handled);
    try std.testing.expect(!scripts.ShouldRun(Click(world.mPanel, world.mLabel, .BUTTON_LEFT)));

    //anything else still gets through: the other button's click, and the same label clicked with another button
    try std.testing.expect(scripts.ShouldRun(Click(world.mPanel, world.mOther, .BUTTON_LEFT)));
    try std.testing.expect(scripts.ShouldRun(Click(world.mPanel, world.mLabel, .BUTTON_RIGHT)));

    //a new batch starts with nothing handled
    scripts.Reset();
    try std.testing.expect(scripts.ShouldRun(Click(world.mPanel, world.mLabel, .BUTTON_LEFT)));
}

test "an enter or exit is each entity's own, so handling one stops nothing" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    var scripts: EventScripts = .{};

    const enter_button = PointerEvent{ .PointerEnter = .{ .mEntity = world.mButton } };
    scripts.After(enter_button, .Handled);
    try std.testing.expect(scripts.ShouldRun(PointerEvent{ .PointerEnter = .{ .mEntity = world.mPanel } }));
    try std.testing.expect(EventScripts.MomentOf(enter_button) == null);
}

test "UI events stop the same way, by what they are about" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    var scripts: EventScripts = .{};

    const submitted = UIEvent{ .TextSubmitted = .{ .mEntity = world.mButton, .mTarget = world.mLabel } };
    scripts.After(submitted, .Handled);
    try std.testing.expect(!scripts.ShouldRun(UIEvent{ .TextSubmitted = .{ .mEntity = world.mPanel, .mTarget = world.mLabel } }));
    //a different kind of event about the same text input still goes up
    try std.testing.expect(scripts.ShouldRun(UIEvent{ .FocusLost = .{ .mEntity = world.mPanel, .mTarget = world.mLabel } }));
}

test "an event for an entity that is gone, or for no entity at all, runs nothing" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    var scripts: EventScripts = .{};

    try world.mOther.Delete(engine_context);
    var callback_list: std.DoublyLinkedList = .{};
    try engine_context.mEditorWorld.ProcessEvents(@import("../../Events/EManagerData.zig"), .EndOfFrame, engine_context, &callback_list);
    try engine_context.mEditorWorld.ProcessEvents(@import("../../Events/ECSEventData.zig"), .EndOfFrame, engine_context, &callback_list);
    try std.testing.expect(!scripts.ShouldRun(Click(world.mOther, world.mOther, .BUTTON_LEFT)));
    try std.testing.expect(!scripts.ShouldRun(UIEvent{ .Default = .{} }));
}
