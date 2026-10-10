//! The number field system on real entities: dragging a field changes its AttribComponent by type (smoothly, in whole
//! steps, never below 0 for a u32) within its limits, typing into it and keeping the edit sets the number typed, and its
//! text keeps showing its value. Drags and clicks are handed to the UIManager the way the editor hands over the frame's
//! pointer events. No window or font needed. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const UIEvent = @import("../../Events/UIEventData.zig").EventT;
const UIManager = @import("../../UI/UIManager.zig");
const Widgets = @import("../../UI/Widgets.zig");
const Vec3 = @import("../../Math/MathTypes.zig").Vec3;

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const AttribComponent = EntityComponents.AttribComponent;
const TextComponent = EntityComponents.TextComponent;
const NumberFieldComponent = @import("../../ECSComponents/UIComponents.zig").NumberFieldComponent;

/// A panel to put fields in
const TestWorld = struct {
    mEngineContext: *EngineContext,
    mPanel: Entity = .uninit,

    fn Init() !*TestWorld {
        const self = try std.heap.page_allocator.create(TestWorld);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        try engine_context.mUIManager.Init(engine_context.EngineAllocator());
        try engine_context.mEditorWorld.Init(engine_context.EngineAllocator());
        const scene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
        self.mPanel = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        engine_context.mPointerSystem.Deinit(engine_context.EngineAllocator());
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    fn Field(self: *TestWorld, value: AttribComponent.ValueTypes, settings: NumberFieldComponent) !Entity {
        return Widgets.NumberField(self.mEngineContext, .{ .Entity = self.mPanel }, value, settings);
    }

    /// A left button drag over a field's text: started, moved by each of `steps` sideways, and let go. Each pointer
    /// event goes to the text, the field and the panel, the way the pointer system sends them
    fn Drag(self: *TestWorld, field: Entity, steps: []const f32) !void {
        const label = UIManager.LabelOf(field).?;
        const chain = [_]Entity{ label, field, self.mPanel };
        const ui = &self.mEngineContext.mUIManager;
        for (chain) |entity| try ui.OnPointerEvent(self.mEngineContext, .{ .PointerDragStart = .{ .mEntity = entity, .mButton = .BUTTON_LEFT, .mTarget = label } });
        var total: f32 = 0;
        for (steps) |step| {
            total += step;
            for (chain) |entity| {
                try ui.OnPointerEvent(self.mEngineContext, .{ .PointerDrag = .{
                    .mEntity = entity,
                    .mButton = .BUTTON_LEFT,
                    .mDelta = .{ .x = step, .y = 0, .z = 0 },
                    .mTotal = .{ .x = total, .y = 0, .z = 0 },
                    .mTarget = label,
                } });
            }
        }
        for (chain) |entity| try ui.OnPointerEvent(self.mEngineContext, .{ .PointerDragEnd = .{ .mEntity = entity, .mButton = .BUTTON_LEFT, .mTotal = .{ .x = total, .y = 0, .z = 0 }, .mTarget = label } });
    }

    /// A double click on a field's text, then `typed` in place of its text, kept with Enter, and the frame's UI events
    /// handed out
    fn TypeInto(self: *TestWorld, field: Entity, typed: []const u8) !void {
        const engine_context = self.mEngineContext;
        const label = UIManager.LabelOf(field).?;
        for ([_]Entity{ label, field, self.mPanel }) |entity| {
            try engine_context.mUIManager.OnPointerEvent(engine_context, .{ .PointerClicked = .{ .mEntity = entity, .mButton = .BUTTON_LEFT, .mClicks = 2, .mPosition = .{ .x = 0, .y = 0, .z = 0 }, .mTarget = label } });
        }
        const focus = &engine_context.mUIManager.mFocusSystem;
        try std.testing.expectEqual(label.mID, focus.Focused().?.mID);
        for (0..TextOf(field).len) |_| try focus.OnKeyPressed(engine_context, .{ ._InputCode = .BACKSPACE, ._Repeat = 0 });
        try focus.OnTextTyped(engine_context, typed);
        try focus.OnKeyPressed(engine_context, .{ ._InputCode = .RETURN, ._Repeat = 0 });
        _ = try self.ProcessUIEvents();
    }

    /// The frame's UI events handed out, the way the editor does, and which entities got a ValueChanged
    fn ProcessUIEvents(self: *TestWorld) ![]Entity {
        const Collector = struct {
            mTo: std.ArrayList(Entity) = .empty,
            mAllocator: std.mem.Allocator,
            fn OnEvent(collector: *@This(), _: *EngineContext, event: *const UIEvent) !@import("../../Events/EventManager.zig").EventResult {
                switch (event.*) {
                    .ValueChanged => |e| try collector.mTo.append(collector.mAllocator, e.mEntity),
                    else => {},
                }
                return .Continue;
            }
        };
        var collector = Collector{ .mAllocator = self.mEngineContext.FrameAllocator() };
        var callback = UIManager.EventManagerT.MakeCallback(Collector, Collector.OnEvent, &collector);
        var callback_list: std.DoublyLinkedList = .{};
        callback_list.append(&callback.mNode);
        try self.mEngineContext.mUIManager.ProcessUIEvents(self.mEngineContext, callback_list);
        return collector.mTo.items;
    }

    fn TextOf(field: Entity) []const u8 {
        return UIManager.LabelOf(field).?.GetComponent(TextComponent).?.mText.items;
    }
};

fn ValueOf(field: Entity) AttribComponent.ValueTypes {
    return field.GetComponent(AttribComponent).?.mData;
}

test "dragging a float field changes it smoothly by its speed, and tells the field and what it is in" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const field = try world.Field(.{ .float32 = 1 }, .{ .mSpeed = 0.5 });

    try world.Drag(field, &.{ 1, 2, -0.5 });
    try std.testing.expectApproxEqAbs(@as(f32, 2.25), ValueOf(field).float32, 0.0001);
    //one change per drag step, each to the field and the panel
    const told = try world.ProcessUIEvents();
    try std.testing.expectEqual(@as(usize, 6), told.len);
    try std.testing.expectEqual(field.mID, told[0].mID);
    try std.testing.expectEqual(world.mPanel.mID, told[1].mID);
}

test "dragging a whole number field steps it, keeping what is left over for the rest of the drag" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const field = try world.Field(.{ .int32 = 0 }, .{ .mSpeed = 0.1 });

    //each step alone is under half a step, but they add up: 0.3, 0.6 -> 1, 0.9, 1.2, 1.5 -> 2
    try world.Drag(field, &.{ 3, 3, 3, 3, 3 });
    try std.testing.expectEqual(@as(i32, 2), ValueOf(field).int32);
    try world.Drag(field, &.{ -50, -50 });
    try std.testing.expectEqual(@as(i32, -8), ValueOf(field).int32);
}

test "a u32 field never goes below 0, and every field keeps within its limits" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const count = try world.Field(.{ .uint32 = 2 }, .{ .mSpeed = 1 });
    //and turning back mid-drag counts from 0, not from below it
    try world.Drag(count, &.{ -10, 3 });
    try std.testing.expectEqual(@as(u32, 3), ValueOf(count).uint32);

    const volume = try world.Field(.{ .float32 = 0.5 }, .{ .mSpeed = 0.1, .mMin = 0, .mMax = 1 });
    try world.Drag(volume, &.{100});
    try std.testing.expectEqual(@as(f32, 1), ValueOf(volume).float32);
    //dragging back starts from the limit, not from where the pointer overshot to
    try world.Drag(volume, &.{-1});
    try std.testing.expectApproxEqAbs(@as(f32, 0.9), ValueOf(volume).float32, 0.0001);
}

test "a size field moves by a share of itself, and Shift drags slower" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    //a lowest value and no highest: 1% of itself per unit, so 100 moves by 1
    const width = try world.Field(.{ .float32 = 100 }, .{ .mSpeed = 0.5, .mMin = 0 });
    try world.Drag(width, &.{10});
    try std.testing.expectApproxEqAbs(@as(f32, 110), ValueOf(width).float32, 0.0001);

    //at 0 it still moves, by 2% of its speed per unit
    const gap = try world.Field(.{ .float32 = 0 }, .{ .mSpeed = 0.5, .mMin = 0 });
    try world.Drag(gap, &.{10});
    try std.testing.expectApproxEqAbs(@as(f32, 0.1), ValueOf(gap).float32, 0.0001);

    //Shift held: a tenth as far, for any field
    const input = &engine_context.mInputManager;
    defer input.Deinit(engine_context.EngineAllocator());
    try input._KeyPressedSet.put(engine_context.EngineAllocator(), .LSHIFT, 0);
    const offset = try world.Field(.{ .float32 = 0 }, .{ .mSpeed = 0.5 });
    try world.Drag(offset, &.{10});
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), ValueOf(offset).float32, 0.0001);
}

test "typing a number into a field sets it within its limits, and anything else puts its value back" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const field = try world.Field(.{ .float32 = 1 }, .{ .mMax = 10, .mDecimals = 2 });

    try world.TypeInto(field, "4.5");
    try std.testing.expectEqual(@as(f32, 4.5), ValueOf(field).float32);
    try std.testing.expectEqualStrings("4.50", TestWorld.TextOf(field));

    try world.TypeInto(field, "250");
    try std.testing.expectEqual(@as(f32, 10), ValueOf(field).float32);
    try std.testing.expectEqualStrings("10.00", TestWorld.TextOf(field));

    try world.TypeInto(field, "lots");
    try std.testing.expectEqual(@as(f32, 10), ValueOf(field).float32);
    try std.testing.expectEqualStrings("10.00", TestWorld.TextOf(field));

    const whole = try world.Field(.{ .int32 = 0 }, .{});
    try world.TypeInto(whole, " -3.6 ");
    try std.testing.expectEqual(@as(i32, -4), ValueOf(whole).int32);
}

test "a field shows its value from the start, and again whenever code sets it, but not while it is typed into" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const field = try world.Field(.{ .float32 = 0.26 }, .{ .mDecimals = 1 });
    try std.testing.expectEqualStrings("0.3", TestWorld.TextOf(field));

    field.GetComponent(AttribComponent).?.mData = .{ .float32 = 7 };
    try engine_context.mUIManager.mNumberFieldSystem.Update(engine_context);
    try std.testing.expectEqualStrings("7.0", TestWorld.TextOf(field));

    //being typed into, its text is the player's until the edit ends
    const label = UIManager.LabelOf(field).?;
    _ = try engine_context.mUIManager.mFocusSystem.Focus(engine_context, label);
    try engine_context.mUIManager.mFocusSystem.OnTextTyped(engine_context, "1");
    try engine_context.mUIManager.mNumberFieldSystem.Update(engine_context);
    try std.testing.expectEqualStrings("7.01", TestWorld.TextOf(field));
    //and dragging leaves the value alone meanwhile
    try world.Drag(field, &.{50});
    try std.testing.expectEqual(@as(f32, 7), ValueOf(field).float32);
}

test "values keep their type through floats" {
    var value: AttribComponent.ValueTypes = .{ .uint32 = 3 };
    value.SetFromFloat(-2);
    try std.testing.expectEqual(@as(u32, 0), value.uint32);
    value = .{ .int32 = 0 };
    value.SetFromFloat(2.5);
    try std.testing.expectEqual(@as(i32, 3), value.int32);
    value = .{ .bool = false };
    value.SetFromFloat(0.1);
    try std.testing.expect(value.bool);
    try std.testing.expectEqual(@as(f64, 1), value.AsFloat());
}
