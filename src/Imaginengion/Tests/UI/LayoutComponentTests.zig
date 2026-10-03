//! LayoutComponent and LayoutItemComponent: what they save, and what they hand the layout algorithm. No window or
//! renderer needed. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const TextSerializer = @import("../../Serializer/TextSerializer.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const Layout = @import("../../UI/Layout.zig");

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const LayoutComponent = EntityComponents.LayoutComponent;
const LayoutItemComponent = EntityComponents.LayoutItemComponent;

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
        try engine_context.mEditorWorld.Init(engine_context.EngineAllocator());
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        engine_context.mEditorWorld.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
        self.mTmpDir.cleanup();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    /// A path in this test's temporary folder, relative to the working directory like the serializer expects
    fn FilePath(self: *TestWorld, file_name: []const u8) ![]const u8 {
        return std.fmt.allocPrint(self.mEngineContext.FrameAllocator(), ".zig-cache/tmp/{s}/{s}", .{ self.mTmpDir.sub_path, file_name });
    }
};

/// A container with nothing left at its default
const CONTAINER = LayoutComponent{
    .mDirection = .Row,
    .mPadding = .{ .Left = 1, .Right = 2, .Top = 3, .Bottom = 4 },
    .mGap = 7.5,
    .mMainAlign = .Center,
    .mCrossAlign = .Center,
    .mColumns = .{ .Count = 4 },
};

/// An item with nothing left at its default
const ITEM = LayoutItemComponent{
    .mWidth = .{ .Percent = 0.25 },
    .mHeight = .{ .Fill = 2 },
    .mPlacement = .{ .Anchored = .{
        .Anchor = .{ .x = 1, .y = -1 },
        .Pivot = .{ .x = 0.5, .y = -0.5 },
        .Offset = .{ .x = -8, .y = 12 },
    } },
    .mCollapsed = true,
    .mComputedSize = .{ .x = 123, .y = 456 },
};

fn ExpectContainer(expected: LayoutComponent, actual: LayoutComponent) !void {
    try std.testing.expectEqual(expected.mDirection, actual.mDirection);
    try std.testing.expectEqual(expected.mPadding, actual.mPadding);
    try std.testing.expectEqual(expected.mGap, actual.mGap);
    try std.testing.expectEqual(expected.mMainAlign, actual.mMainAlign);
    try std.testing.expectEqual(expected.mCrossAlign, actual.mCrossAlign);
    try std.testing.expectEqual(expected.mColumns, actual.mColumns);
}

fn ExpectItemSettings(expected: LayoutItemComponent, actual: LayoutItemComponent) !void {
    try std.testing.expectEqual(expected.mWidth, actual.mWidth);
    try std.testing.expectEqual(expected.mHeight, actual.mHeight);
    try std.testing.expectEqual(expected.mPlacement, actual.mPlacement);
    try std.testing.expectEqual(expected.mCollapsed, actual.mCollapsed);
}

test "layout components round trip, all but the computed size" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    const panel = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try panel.AddComponent(engine_context, CONTAINER);
    _ = try panel.AddComponent(engine_context, ITEM);
    //the other kinds of sizing and placement, on a second item
    const label = try panel.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    const other_item = LayoutItemComponent{ .mWidth = .{ .Fixed = 64 }, .mHeight = .Fit };
    _ = try label.AddComponent(engine_context, other_item);

    const path = try world.FilePath("panel.imen");
    try TextSerializer.SerializeECSObject(engine_context, panel, path);
    const loaded = try scene.CreateEntity(engine_context, Entity.BlankConfig);
    try TextSerializer.DeserializeECSObj(engine_context, loaded, path);

    try ExpectContainer(CONTAINER, loaded.GetComponent(LayoutComponent).?.*);
    const loaded_item = loaded.GetComponent(LayoutItemComponent).?.*;
    try ExpectItemSettings(ITEM, loaded_item);
    //worked out again when the tree is laid out, never read from the file
    try std.testing.expectEqual(@as(f32, 0), loaded_item.mComputedSize.x);
    try std.testing.expectEqual(@as(f32, 0), loaded_item.mComputedSize.y);

    var children = loaded.GetIterator(.Child);
    const loaded_label = children.next().?;
    try ExpectItemSettings(other_item, loaded_label.GetComponent(LayoutItemComponent).?.*);
    try std.testing.expect(!loaded_label.HasComponent(LayoutComponent));
}

test "a container hands the layout algorithm every one of its settings" {
    const container = CONTAINER.ToContainer();
    try std.testing.expectEqual(Layout.Direction.Row, container.Direction);
    try std.testing.expectEqual(CONTAINER.mPadding, container.Padding);
    try std.testing.expectEqual(@as(f32, 7.5), container.Gap);
    try std.testing.expectEqual(Layout.MainAlign.Center, container.MainAlign);
    try std.testing.expectEqual(Layout.CrossAlign.Center, container.CrossAlign);
}

test "an item hands the layout algorithm its settings" {
    const node = ITEM.ToNode();
    try std.testing.expectEqual(ITEM.mWidth, node.Width);
    try std.testing.expectEqual(ITEM.mHeight, node.Height);
    try std.testing.expectEqual(ITEM.mPlacement, node.Placement);
    try std.testing.expect(node.Collapsed);
    //the layout pass fills these in from the entity's other components and its place in the tree
    try std.testing.expect(node.Container == null);
    try std.testing.expect(node.Content == .None);
    try std.testing.expect(node.FirstChild == null and node.NextSibling == null);

    //and the default item is a fit, flowed one: what a container without an item is laid out as
    const default_node = (LayoutItemComponent{}).ToNode();
    try std.testing.expectEqual(Layout.Sizing.Fit, default_node.Width);
    try std.testing.expectEqual(Layout.Sizing.Fit, default_node.Height);
    try std.testing.expect(default_node.Placement == .Flow);
}

test "a duplicated entity keeps its layout components" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    const panel = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try panel.AddComponent(engine_context, CONTAINER);
    _ = try panel.AddComponent(engine_context, ITEM);

    const copy = try panel.Duplicate(engine_context);
    try ExpectContainer(CONTAINER, copy.GetComponent(LayoutComponent).?.*);
    try ExpectItemSettings(ITEM, copy.GetComponent(LayoutItemComponent).?.*);
}
