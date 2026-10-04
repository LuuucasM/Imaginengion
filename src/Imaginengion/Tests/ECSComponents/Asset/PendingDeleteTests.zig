//! PendingDelete marks an asset whose file has gone missing. It used to be a side hash map in
//! AManager that nothing ever removed, so a destroyed asset left its mark behind and the sweep kept
//! re-queueing ToDestroyAsset against a dead (or recycled) id. As a component it cannot outlive the
//! asset, which is what these tests pin. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../../Core/EngineContext.zig");
const Assets = @import("../../../ECSComponents/AComponents.zig");
const PendingDelete = Assets.PendingDelete;

/// An EngineContext with just enough set up for the asset manager. No Setup: its default assets
/// need the GPU, and nothing here loads an asset.
const TestContext = struct {
    mEngineContext: *EngineContext,

    fn Init() !*TestContext {
        const self = try std.heap.page_allocator.create(TestContext);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        //UUIDs and timestamps go through the context's Io, which forwards to this
        engine_context._Internal.ThreadedIO = std.Io.Threaded.init(engine_context._Internal.EngineGPA.allocator(), .{
            .concurrent_limit = .nothing,
            .async_limit = .nothing,
        });
        try engine_context.mAssetManager.Init(engine_context);
        return self;
    }

    fn Deinit(self: *TestContext) void {
        const engine_context = self.mEngineContext;
        const engine_allocator = engine_context.EngineAllocator();

        //the asset manager, minus the default assets Init never set up and the working directory
        //handle it does not own
        const asset_manager = &engine_context.mAssetManager;
        asset_manager.mECSManager.Deinit(engine_context);
        asset_manager.mUUIDToWorldID.deinit(engine_allocator);
        asset_manager.mEventManager.Deinit(engine_allocator);
        asset_manager.mCWDPath.deinit(engine_allocator);

        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }
};

test "a destroyed asset takes its PendingDelete with it" {
    const test_context = try TestContext.Init();
    defer test_context.Deinit();
    const engine_context = test_context.mEngineContext;
    const asset_manager = &engine_context.mAssetManager;
    const engine_allocator = engine_context.EngineAllocator();

    const asset_id = try asset_manager.mECSManager.CreateEntity(engine_allocator);
    _ = try asset_manager.mECSManager.AddComponent(engine_allocator, asset_id, PendingDelete{
        .mReason = 1,
        .mTime = std.Io.Timestamp.now(engine_context.Io(), .awake),
    });

    try std.testing.expect(asset_manager.mECSManager.HasComponent(PendingDelete, asset_id));
    try std.testing.expectEqual(@as(usize, 1), asset_manager.mECSManager.NumWithComponent(PendingDelete));

    //destroying the asset is what the sweep eventually asks for once the grace period is up
    try asset_manager.mECSManager.DestroyEntity(engine_context, asset_id);
    var callback_list: std.DoublyLinkedList = .{};
    try asset_manager.mECSManager.ProcessEvents(engine_context, .EndOfFrame, &callback_list);

    //the mark is gone with the asset. The old hash map kept it, and the next sweep re-queued a
    //destroy for an id that no longer existed
    try std.testing.expect(!asset_manager.mECSManager.IsActiveEntity(asset_id));
    try std.testing.expectEqual(@as(usize, 0), asset_manager.mECSManager.NumWithComponent(PendingDelete));

    const pending = try asset_manager.mECSManager.GetGroup(engine_context.FrameAllocator(), .{ .Component = PendingDelete });
    try std.testing.expectEqual(@as(usize, 0), pending.items.len);
}

test "marking is per asset and leaves others alone" {
    const test_context = try TestContext.Init();
    defer test_context.Deinit();
    const engine_context = test_context.mEngineContext;
    const asset_manager = &engine_context.mAssetManager;
    const engine_allocator = engine_context.EngineAllocator();

    const marked = try asset_manager.mECSManager.CreateEntity(engine_allocator);
    const untouched = try asset_manager.mECSManager.CreateEntity(engine_allocator);

    _ = try asset_manager.mECSManager.AddComponent(engine_allocator, marked, PendingDelete{
        .mReason = 1,
        .mTime = std.Io.Timestamp.now(engine_context.Io(), .awake),
    });

    const pending = try asset_manager.mECSManager.GetGroup(engine_context.FrameAllocator(), .{ .Component = PendingDelete });
    try std.testing.expectEqual(@as(usize, 1), pending.items.len);
    try std.testing.expectEqual(marked, pending.items[0]);
    try std.testing.expect(!asset_manager.mECSManager.HasComponent(PendingDelete, untouched));
}

test "a mark can come off again, for a file that was only briefly missing" {
    const test_context = try TestContext.Init();
    defer test_context.Deinit();
    const engine_context = test_context.mEngineContext;
    const asset_manager = &engine_context.mAssetManager;
    const engine_allocator = engine_context.EngineAllocator();

    const asset_id = try asset_manager.mECSManager.CreateEntity(engine_allocator);
    _ = try asset_manager.mECSManager.AddComponent(engine_allocator, asset_id, PendingDelete{
        .mReason = 1,
        .mTime = std.Io.Timestamp.now(engine_context.Io(), .awake),
    });

    //the sweep clears the mark synchronously, so the same OnUpdate no longer sees the asset as
    //pending rather than it lingering until end of frame
    try asset_manager.mECSManager.RemoveComponentSync(engine_context, asset_id, @TypeOf(asset_manager.mECSManager).ComponentInd(PendingDelete));

    try std.testing.expect(!asset_manager.mECSManager.HasComponent(PendingDelete, asset_id));
    try std.testing.expect(asset_manager.mECSManager.IsActiveEntity(asset_id));

    //and it can be marked again later
    _ = try asset_manager.mECSManager.AddComponent(engine_allocator, asset_id, PendingDelete{
        .mReason = 1,
        .mTime = std.Io.Timestamp.now(engine_context.Io(), .awake),
    });
    try std.testing.expect(asset_manager.mECSManager.HasComponent(PendingDelete, asset_id));
}
