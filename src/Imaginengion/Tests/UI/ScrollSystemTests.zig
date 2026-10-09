//! The scroll system on real entities: scrollbar thumbs appearing, sized and placed for how much is in view and how
//! far it is scrolled, the wheel going to the right region, and dragging a thumb. Each frame runs layout, the scroll
//! system and world transforms in the editor's order. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const Vec3 = @import("../../Math/MathTypes.zig").Vec3;
const LayoutSystem = @import("../../UI/LayoutSystem.zig");
const ScrollSystem = @import("../../UI/ScrollSystem.zig");
const PhysicsManager = @import("../../Physics/PhysicsManager.zig");

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const ClipComponent = EntityComponents.ClipComponent;
const UIElementComponent = EntityComponents.UIElementComponent;
const UIManager = @import("../../UI/UIManager.zig");
const UIComponents = @import("../../ECSComponents/UIComponents.zig");
const ScrollComponent = UIComponents.ScrollComponent;
const ScrollStateComponent = UIComponents.ScrollStateComponent;
const LayoutComponent = EntityComponents.LayoutComponent;
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const ShapeComponent = EntityComponents.ShapeComponent;
const SurfaceComponent = EntityComponents.SurfaceComponent;
const TransformComponent = EntityComponents.TransformComponent;
const SceneComponent = @import("../../ECSComponents/SComponents.zig").SceneComponent;
const EntityChildComponent = @import("../../ECS/Components.zig").ChildComponent(Entity.Type);

const SEventData = @import("../../Events/SManagerData.zig");
const EEventData = @import("../../Events/EManagerData.zig");
const ECSEventData = @import("../../Events/ECSEventData.zig");

const eps: f32 = 0.01;

/// An 80 x 60 strip that scrolls sideways, holding a 100 x 50 list that scrolls up and down, which holds three 100 x
/// 30 rows: the list runs 20 past the strip, the rows 40 past the list
const TestWorld = struct {
    mEngineContext: *EngineContext,
    mStrip: Entity = .uninit,
    mList: Entity = .uninit,
    mRows: [3]Entity = undefined,

    fn Init() !*TestWorld {
        const self = try std.heap.page_allocator.create(TestWorld);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        try engine_context.mUIManager.Init(engine_context.EngineAllocator());
        try engine_context.mEditorWorld.Init(engine_context.EngineAllocator());

        const scene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
        scene.GetComponent(SceneComponent).?.mLayoutArea = .{ .x = 1920, .y = 1080 };

        self.mStrip = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
        try Region(engine_context, self.mStrip, 80, 60, .Row, .{ .mScroll = .Horizontal });
        self.mList = try self.mStrip.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
        try Region(engine_context, self.mList, 100, 50, .Column, .{ .mScroll = .Vertical, .mWheelStep = 15 });
        for (&self.mRows) |*row| {
            row.* = try self.mList.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
            _ = try row.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fixed = 100 }, .mHeight = .{ .Fixed = 30 } });
        }
        return self;
    }

    /// A scrolling region: a sized layout container with a clip, whose UI element scrolls the way `scroll` says
    fn Region(engine_context: *EngineContext, entity: Entity, width: f32, height: f32, direction: @import("../../UI/Layout.zig").Direction, scroll: ScrollComponent) !void {
        _ = try entity.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fixed = width }, .mHeight = .{ .Fixed = height } });
        _ = try entity.AddComponent(engine_context, LayoutComponent{ .mDirection = direction });
        _ = try entity.AddComponent(engine_context, ClipComponent{});
        _ = try entity.AddComponent(engine_context, UIElementComponent{});
        _ = try UIManager.ElementOf(entity).?.AddComponent(engine_context, scroll);
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

    /// The editor's frame from layout on: layout, then the scroll system, then world transforms
    fn Frame(self: *TestWorld) !void {
        const engine_context = self.mEngineContext;
        const world = &engine_context.mEditorWorld;
        try LayoutSystem.UpdateLayouts(world, engine_context);
        try engine_context.mUIManager.mScrollSystem.Update(engine_context, world);
        try PhysicsManager.UpdateWorldTransforms(world, engine_context);
    }

    fn Wheel(self: *TestWorld, over: Entity, notches_x: f32, notches_y: f32) !void {
        const engine_context = self.mEngineContext;
        try engine_context.mPointerSystem.Update(engine_context, .{ .Target = over });
        try engine_context.mUIManager.mScrollSystem.OnWheel(engine_context, &engine_context.mPointerSystem, notches_x, notches_y);
    }

    fn EndFrame(self: *TestWorld) !void {
        const engine_context = self.mEngineContext;
        const world = &engine_context.mEditorWorld;
        var callback_list: std.DoublyLinkedList = .{};
        try world.ProcessEvents(SEventData, .EndOfFrame, engine_context, &callback_list);
        try world.ProcessEvents(EEventData, .EndOfFrame, engine_context, &callback_list);
        try world.ProcessEvents(ECSEventData, .EndOfFrame, engine_context, &callback_list);
    }
};

/// How far a region is scrolled, and its scrollbars: its UI element's scroll state
fn Clip(entity: Entity) *ScrollStateComponent {
    return UIManager.GetUIComponent(entity, ScrollStateComponent).?;
}

fn ExpectThumb(thumb: Entity, width: f32, height: f32, x: f32, y: f32) !void {
    try std.testing.expect(thumb.GetComponent(SurfaceComponent).?.mShouldRender);
    const quad = thumb.GetComponent(ShapeComponent).?.GetQuad().?;
    try std.testing.expectApproxEqAbs(width, quad.Size.x, eps);
    try std.testing.expectApproxEqAbs(height, quad.Size.y, eps);
    const translation = thumb.GetComponent(TransformComponent).?.GetTranslation();
    try std.testing.expectApproxEqAbs(x, translation.x, eps);
    try std.testing.expectApproxEqAbs(y, translation.y, eps);
}

const THICK = ScrollSystem.THUMB_THICKNESS;

test "a region its children run past gets a thumb along that edge, as long as the part in view" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    try world.Frame();

    const list = Clip(world.mList);
    try std.testing.expectApproxEqAbs(@as(f32, 90), list.mContentSize.y, eps);
    //50 of 90 in view: a thumb 50 * 50 / 90 long, at the top of the right edge
    const length: f32 = 50.0 * 50.0 / 90.0;
    const thumb = list.mThumbY.?;
    try std.testing.expectEqual(world.mList.mID, thumb.GetComponent(EntityChildComponent).?.mParent);
    //colored by the theme, hovered and dragged too
    try std.testing.expectEqualStrings("Scrollbar", UIManager.GetUIComponent(thumb, UIComponents.StyleComponent).?.mStyle.items);
    try ExpectThumb(thumb, THICK, length, 50 - THICK / 2, 25 - length / 2);
    //it doesn't scroll sideways, so no thumb that way
    try std.testing.expect(list.mThumbX == null);

    //the strip: 80 of 100 across, along its bottom edge from the left
    const strip_length: f32 = 80.0 * 80.0 / 100.0;
    try ExpectThumb(Clip(world.mStrip).mThumbX.?, strip_length, THICK, -40 + strip_length / 2, -30 + THICK / 2);
}

test "the wheel scrolls the nearest region under the pointer that scrolls that way, kept in range" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    try world.Frame();

    //one notch down over a row: the list scrolls, the strip around it doesn't
    try world.Wheel(world.mRows[1], 0, -1);
    try world.Frame();
    try std.testing.expectApproxEqAbs(@as(f32, 15), Clip(world.mList).mOffset.y, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 0), Clip(world.mStrip).mOffset.x, eps);
    //the rows went up with it
    try std.testing.expectApproxEqAbs(@as(f32, 10 + 15), world.mRows[0].GetComponent(TransformComponent).?.GetTranslation().y, eps);

    //sideways goes to the strip, the list doesn't scroll that way. Its notch is the default 40, more than the 20 it
    //has to scroll
    try world.Wheel(world.mRows[1], 1, 0);
    try world.Frame();
    try std.testing.expectApproxEqAbs(@as(f32, 20), Clip(world.mStrip).mOffset.x, eps);

    //far past the end: stops at the end, with the thumb at the bottom
    try world.Wheel(world.mRows[1], 0, -10);
    try world.Frame();
    try std.testing.expectApproxEqAbs(@as(f32, 40), Clip(world.mList).mOffset.y, eps);
    const length: f32 = 50.0 * 50.0 / 90.0;
    try ExpectThumb(Clip(world.mList).mThumbY.?, THICK, length, 50 - THICK / 2, -25 + length / 2);
}

test "dragging a thumb scrolls as much as keeps it under the pointer" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    try world.Frame();

    const thumb = Clip(world.mList).mThumbY.?;
    //10 down the track, which has 50 - 27.8 to travel for 40 of scrolling
    try engine_context.mUIManager.mScrollSystem.OnPointerEvent(engine_context, .{ .PointerDrag = .{
        .mEntity = thumb,
        .mButton = .BUTTON_LEFT,
        .mDelta = .{ .x = 0, .y = -10, .z = 0 },
        .mTotal = .{ .x = 0, .y = -10, .z = 0 },
        .mTarget = thumb,
    } });
    try world.Frame();
    const length: f32 = 50.0 * 50.0 / 90.0;
    try std.testing.expectApproxEqAbs(10 * 40 / (50 - length), Clip(world.mList).mOffset.y, eps);
    try ExpectThumb(thumb, THICK, length, 50 - THICK / 2, 25 - length / 2 - 10);

    //the same drag heard by the list it is in (the chain's other events) changes nothing more
    try engine_context.mUIManager.mScrollSystem.OnPointerEvent(engine_context, .{ .PointerDrag = .{
        .mEntity = world.mList,
        .mButton = .BUTTON_LEFT,
        .mDelta = .{ .x = 0, .y = -10, .z = 0 },
        .mTotal = .{ .x = 0, .y = -10, .z = 0 },
        .mTarget = thumb,
    } });
    try world.Frame();
    try std.testing.expectApproxEqAbs(10 * 40 / (50 - length), Clip(world.mList).mOffset.y, eps);
}

test "a region that no longer overflows loses its thumb" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    try world.Frame();
    const thumb = Clip(world.mList).mThumbY.?;

    world.mList.GetComponent(LayoutItemComponent).?.mHeight = .{ .Fixed = 100 };
    try world.mList.MarkLayoutDirty(engine_context);
    try world.Frame();
    try std.testing.expect(Clip(world.mList).mThumbY == null);
    //hidden now, gone at the end of the frame
    try std.testing.expect(!thumb.GetComponent(SurfaceComponent).?.mShouldRender);
    try world.EndFrame();
    try std.testing.expect(!thumb.IsActive());
}
