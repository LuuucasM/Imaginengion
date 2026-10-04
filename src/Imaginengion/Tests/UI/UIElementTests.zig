//! An entity's UI element (UIElementComponent and the UIManager's elements): every way an entity gets the component
//! leaves it with an element of its own pointing back at it, and an element nothing points at any more is let go at
//! the end of the frame. No window or renderer needed. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const WorldManager = @import("../../Core/WorldManager.zig");
const TextSerializer = @import("../../Serializer/TextSerializer.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const UIElement = @import("../../ECSObjects/UIElement.zig");
const UIManager = @import("../../UI/UIManager.zig");
const UIElementComponent = @import("../../ECSComponents/EComponents.zig").UIElementComponent;

const SEventData = @import("../../Events/SManagerData.zig");
const EEventData = @import("../../Events/EManagerData.zig");
const ECSEventData = @import("../../Events/ECSEventData.zig");

const TestWorld = struct {
    mEngineContext: *EngineContext,
    mTmpDir: std.testing.TmpDir,

    fn Init() !*TestWorld {
        const self = try std.heap.page_allocator.create(TestWorld);
        self.* = .{
            .mEngineContext = try std.heap.page_allocator.create(EngineContext),
            .mTmpDir = std.testing.tmpDir(.{}),
        };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        //UUIDs and file reads/writes go through the context's Io, which forwards to this
        engine_context._Internal.ThreadedIO = std.Io.Threaded.init(engine_context._Internal.EngineGPA.allocator(), .{
            .concurrent_limit = .nothing,
            .async_limit = .nothing,
        });
        try engine_context.mUIManager.Init(engine_context.EngineAllocator());
        try engine_context.mEditorWorld.Init(engine_context.EngineAllocator());
        try engine_context.mSimulateWorld.Init(engine_context.EngineAllocator());
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        engine_context.mSimulateWorld.Deinit(engine_context);
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
        self.mTmpDir.cleanup();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    /// An entity with a UIElementComponent, in a new scene of the editor world
    fn EntityWithElement(self: *TestWorld) !Entity {
        const engine_context = self.mEngineContext;
        const scene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
        const entity = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
        _ = try entity.AddComponent(engine_context, UIElementComponent{});
        return entity;
    }

    /// EditorProgram.OnUpdate's end of frame: the worlds' deletes, then the UIManager's
    fn EndFrame(self: *TestWorld) !void {
        const engine_context = self.mEngineContext;
        for ([_]*WorldManager{ &engine_context.mEditorWorld, &engine_context.mSimulateWorld }) |world| {
            var callback_list: std.DoublyLinkedList = .{};
            try world.ProcessEvents(SEventData, .EndOfFrame, engine_context, &callback_list);
            try world.ProcessEvents(EEventData, .EndOfFrame, engine_context, &callback_list);
            try world.ProcessEvents(ECSEventData, .EndOfFrame, engine_context, &callback_list);
        }
        try engine_context.mUIManager.EndFrame(engine_context);
    }

    fn FilePath(self: *TestWorld, file_name: []const u8) ![]const u8 {
        return std.fmt.allocPrint(self.mEngineContext.FrameAllocator(), ".zig-cache/tmp/{s}/{s}", .{ self.mTmpDir.sub_path, file_name });
    }
};

/// `entity` has an element, and that element points back at it
fn ExpectOwnElement(entity: Entity) !UIElement {
    const element = UIManager.ElementOf(entity) orelse return error.TestExpectedElement;
    const owner = element.GetOwner();
    try std.testing.expectEqual(entity.mID, owner.mID);
    try std.testing.expectEqual(entity.mManager, owner.mManager);
    return element;
}

test "adding a UIElementComponent gives the entity an element that points back at it" {
    const world = try TestWorld.Init();
    defer world.Deinit();

    const entity = try world.EntityWithElement();
    const element = try ExpectOwnElement(entity);
    //and it lasts past the end of the frame
    try world.EndFrame();
    try std.testing.expect(element.IsActive());
}

test "removing the component or deleting the entity lets the element go at the end of the frame" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const removed = try world.EntityWithElement();
    const removed_element = try ExpectOwnElement(removed);
    const deleted = try world.EntityWithElement();
    const deleted_element = try ExpectOwnElement(deleted);

    try removed.RemoveComponent(engine_context, UIElementComponent);
    try deleted.Delete(engine_context);
    try world.EndFrame();
    try std.testing.expect(!removed_element.IsActive());
    try std.testing.expect(!deleted_element.IsActive());
}

test "an element no entity points at is let go of" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const stray = try engine_context.mUIManager.NewElement(engine_context);
    try world.EndFrame();
    try std.testing.expect(!stray.IsActive());

    //nor one an entity has moved on from: given a new element, the old one goes
    const entity = try world.EntityWithElement();
    const old = try ExpectOwnElement(entity);
    entity.GetComponent(UIElementComponent).?.mElement = .uninit;
    try engine_context.mUIManager.Adopt(engine_context, entity);
    const new = try ExpectOwnElement(entity);
    try std.testing.expect(old.mID != new.mID);
    try world.EndFrame();
    try std.testing.expect(!old.IsActive());
    try std.testing.expect(new.IsActive());
}

test "a duplicated entity gets an element of its own" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const original = try world.EntityWithElement();
    const original_element = try ExpectOwnElement(original);
    const copy = try original.Duplicate(engine_context);
    const copy_element = try ExpectOwnElement(copy);
    try std.testing.expect(original_element.mID != copy_element.mID);

    //the original's is still the original's, and neither is let go
    _ = try ExpectOwnElement(original);
    try world.EndFrame();
    try std.testing.expect(original_element.IsActive());
    try std.testing.expect(copy_element.IsActive());
}

test "a copied world's entities get elements of their own, which go when that world is cleared" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const original = try world.EntityWithElement();
    const original_element = try ExpectOwnElement(original);

    //what pressing play does
    try engine_context.mEditorWorld.Copy(engine_context, &engine_context.mSimulateWorld);
    const copy = engine_context.mSimulateWorld.GetEntity(original.mID);
    const copy_element = try ExpectOwnElement(copy);
    try std.testing.expect(original_element.mID != copy_element.mID);
    _ = try ExpectOwnElement(original);

    //and stopping
    engine_context.mSimulateWorld.clearAndFree(engine_context, .All);
    try world.EndFrame();
    try std.testing.expect(!copy_element.IsActive());
    try std.testing.expect(original_element.IsActive());
}

test "saved and loaded, an entity gets an element of its own" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const original = try world.EntityWithElement();
    const original_element = try ExpectOwnElement(original);

    const path = try world.FilePath("button.imen");
    try TextSerializer.SerializeECSObject(engine_context, original, path);
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    const loaded = try scene.CreateEntity(engine_context, Entity.BlankConfig);
    try TextSerializer.DeserializeECSObj(engine_context, loaded, path);

    const loaded_element = try ExpectOwnElement(loaded);
    try std.testing.expect(original_element.mID != loaded_element.mID);
    try world.EndFrame();
    try std.testing.expect(loaded_element.IsActive());
}

test "an element's UI components are saved and copied with its entity, how far it is scrolled isn't" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const UIComponents = @import("../../ECSComponents/UIComponents.zig");

    const original = try world.EntityWithElement();
    const element = UIManager.ElementOf(original).?;
    _ = try element.AddComponent(engine_context, UIComponents.TextInputComponent{ .mFocusOn = .DoubleClick });
    _ = try element.AddComponent(engine_context, UIComponents.NumberFieldComponent{ .mSpeed = 2, .mMax = 5, .mDecimals = 1 });
    //and the value a number field shows, which is the entity's own
    _ = try original.AddComponent(engine_context, @import("../../ECSComponents/EComponents.zig").AttribComponent{ .mData = .{ .int32 = -7 } });
    _ = try element.AddComponent(engine_context, UIComponents.PopupComponent{ .mPlacement = .{ .Anchor = .{ .x = 1, .y = 1 }, .Pivot = .{ .x = -1, .y = 1 }, .Offset = .{ .x = 3, .y = -4 } } });
    _ = try element.AddComponent(engine_context, UIComponents.ScrollComponent{ .mScroll = .Both, .mWheelStep = 12 });
    //scrolling gets somewhere to keep how far it is scrolled
    const state = element.GetComponent(UIComponents.ScrollStateComponent).?;
    state.mOffset = .{ .x = 5, .y = 6 };

    const path = try world.FilePath("panel.imen");
    try TextSerializer.SerializeECSObject(engine_context, original, path);
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    const loaded = try scene.CreateEntity(engine_context, Entity.BlankConfig);
    try TextSerializer.DeserializeECSObj(engine_context, loaded, path);
    const copy = try original.Duplicate(engine_context);

    for ([_]Entity{ loaded, copy }) |entity| {
        const other = try ExpectOwnElement(entity);
        try std.testing.expectEqual(UIComponents.TextInputComponent.FocusOn.DoubleClick, other.GetComponent(UIComponents.TextInputComponent).?.mFocusOn);
        const number_field = other.GetComponent(UIComponents.NumberFieldComponent).?;
        try std.testing.expectEqual(@as(f32, 2), number_field.mSpeed);
        try std.testing.expectEqual(@as(?f32, null), number_field.mMin);
        try std.testing.expectEqual(@as(?f32, 5), number_field.mMax);
        try std.testing.expectEqual(@as(u8, 1), number_field.mDecimals);
        try std.testing.expectEqual(@as(i32, -7), entity.GetComponent(@import("../../ECSComponents/EComponents.zig").AttribComponent).?.mData.int32);
        const popup = other.GetComponent(UIComponents.PopupComponent).?;
        try std.testing.expectEqual(@as(f32, 1), popup.mPlacement.Anchor.x);
        try std.testing.expectEqual(@as(f32, -4), popup.mPlacement.Offset.y);
        const scroll = other.GetComponent(UIComponents.ScrollComponent).?;
        try std.testing.expectEqual(@import("../../UI/Layout.zig").Scroll.Both, scroll.mScroll);
        try std.testing.expectEqual(@as(f32, 12), scroll.mWheelStep);
        //a fresh scroll state, at the start
        const other_state = other.GetComponent(UIComponents.ScrollStateComponent).?;
        try std.testing.expectEqual(@as(f32, 0), other_state.mOffset.y);
    }
}
