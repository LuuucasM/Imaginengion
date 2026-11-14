//! PendingDelete marks an asset whose file has gone missing. It used to be a side hash map in
//! AManager that nothing ever removed, so a destroyed asset left its mark behind and the sweep kept
//! re-queueing ToDestroyAsset against a dead (or recycled) id. As a component it cannot outlive the
//! asset, which is what these tests pin. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../../Core/EngineContext.zig");
const Assets = @import("../../../ECSComponents/AComponents.zig");
const PendingDelete = Assets.PendingDelete;
const FileMetaData = Assets.FileMetaData;
const AssetHandle = @import("../../../ECSObjects/AssetHandle.zig");

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
        engine_context._Internal.ThreadPool = std.Io.Threaded.init(engine_context._Internal.KeepHeap.allocator(), .{
            .concurrent_limit = .nothing,
            .async_limit = .nothing,
        });
        try engine_context.mAssetManager.Init(engine_context);
        return self;
    }

    fn Deinit(self: *TestContext) void {
        const engine_context = self.mEngineContext;
        const keep_allocator = engine_context.Keep();

        //the asset manager, minus the default assets Init never set up and the working directory
        //handle it does not own
        const asset_manager = &engine_context.mAssetManager;
        asset_manager.mECSManager.Deinit(engine_context);
        asset_manager.mUUIDToWorldID.deinit(keep_allocator);
        asset_manager.mEventManager.Deinit(keep_allocator);
        asset_manager.mCWDPath.deinit(keep_allocator);

        _ = engine_context._Internal.KeepHeap.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }
};

test "a destroyed asset takes its PendingDelete with it" {
    const test_context = try TestContext.Init();
    defer test_context.Deinit();
    const engine_context = test_context.mEngineContext;
    const asset_manager = &engine_context.mAssetManager;
    const keep_allocator = engine_context.Keep();

    const asset_id = try asset_manager.mECSManager.CreateEntity(keep_allocator);
    _ = try asset_manager.mECSManager.AddComponentSync(engine_context, asset_id, PendingDelete{
        .mReason = 1,
        .mTime = std.Io.Timestamp.now(engine_context.Io(), .awake),
    });

    try std.testing.expect(asset_manager.mECSManager.HasComponent(PendingDelete, asset_id));
    try std.testing.expectEqual(@as(usize, 1), asset_manager.mECSManager.NumWithComponent(PendingDelete));

    //destroying the asset is what the sweep eventually asks for once the grace period is up
    try asset_manager.mECSManager.DestroyEntity(engine_context, asset_id);

    //the mark is gone with the asset. The old hash map kept it, and the next sweep re-queued a
    //destroy for an id that no longer existed
    try std.testing.expect(!asset_manager.mECSManager.IsActiveEntity(asset_id));
    try std.testing.expectEqual(@as(usize, 0), asset_manager.mECSManager.NumWithComponent(PendingDelete));

    const pending = try asset_manager.mECSManager.GetGroup(engine_context.Scratch(), .{ .Component = PendingDelete });
    try std.testing.expectEqual(@as(usize, 0), pending.items.len);
}

test "marking is per asset and leaves others alone" {
    const test_context = try TestContext.Init();
    defer test_context.Deinit();
    const engine_context = test_context.mEngineContext;
    const asset_manager = &engine_context.mAssetManager;
    const keep_allocator = engine_context.Keep();

    const marked = try asset_manager.mECSManager.CreateEntity(keep_allocator);
    const untouched = try asset_manager.mECSManager.CreateEntity(keep_allocator);

    _ = try asset_manager.mECSManager.AddComponentSync(engine_context, marked, PendingDelete{
        .mReason = 1,
        .mTime = std.Io.Timestamp.now(engine_context.Io(), .awake),
    });

    const pending = try asset_manager.mECSManager.GetGroup(engine_context.Scratch(), .{ .Component = PendingDelete });
    try std.testing.expectEqual(@as(usize, 1), pending.items.len);
    try std.testing.expectEqual(marked, pending.items[0]);
    try std.testing.expect(!asset_manager.mECSManager.HasComponent(PendingDelete, untouched));
}

test "a mark can come off again, for a file that was only briefly missing" {
    const test_context = try TestContext.Init();
    defer test_context.Deinit();
    const engine_context = test_context.mEngineContext;
    const asset_manager = &engine_context.mAssetManager;
    const keep_allocator = engine_context.Keep();

    const asset_id = try asset_manager.mECSManager.CreateEntity(keep_allocator);
    _ = try asset_manager.mECSManager.AddComponentSync(engine_context, asset_id, PendingDelete{
        .mReason = 1,
        .mTime = std.Io.Timestamp.now(engine_context.Io(), .awake),
    });

    //the sweep clears the mark synchronously, so the same OnUpdate no longer sees the asset as
    //pending rather than it lingering until end of frame
    try asset_manager.mECSManager.RemoveComponentSync(engine_context, asset_id, @TypeOf(asset_manager.mECSManager).ComponentInd(PendingDelete));

    try std.testing.expect(!asset_manager.mECSManager.HasComponent(PendingDelete, asset_id));
    try std.testing.expect(asset_manager.mECSManager.IsActiveEntity(asset_id));

    //and it can be marked again later
    _ = try asset_manager.mECSManager.AddComponentSync(engine_context, asset_id, PendingDelete{
        .mReason = 1,
        .mTime = std.Io.Timestamp.now(engine_context.Io(), .awake),
    });
    try std.testing.expect(asset_manager.mECSManager.HasComponent(PendingDelete, asset_id));
}

test "OnUpdate stats every file on the job pool: a missing one is marked, a changed one is caught up, the rest stay" {
    const test_context = try TestContext.Init();
    defer test_context.Deinit();
    const engine_context = test_context.mEngineContext;
    const asset_manager = &engine_context.mAssetManager;
    const keep_allocator = engine_context.Keep();
    //the test's own file setup: the engine's Io doesn't forward deleting a file
    const io = std.testing.io;

    //a pool of 3 workers besides this thread, so the stats really are spread over threads
    const threads = try std.heap.page_allocator.create(std.Io.Threaded);
    threads.* = std.Io.Threaded.init(std.heap.page_allocator, .{ .async_limit = .limited(3), .concurrent_limit = .nothing });
    engine_context.mJobPool = .{ .mIo = threads.io(), .mWorkers = 3 };
    engine_context._Internal.ThreadScratchArenas.mMainThread = std.Thread.getCurrentId();
    defer {
        engine_context.mJobPool = .{};
        threads.deinit();
        std.heap.page_allocator.destroy(threads);
        engine_context._Internal.ThreadScratchArenas.Deinit();
    }

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    //files tracked as they are now, the way a loaded asset's FileMetaData is
    const count = 40;
    var assets: [count]AssetHandle.Type = undefined;
    for (&assets, 0..) |*asset, i| {
        var name_buf: [32]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "file{d}.txt", .{i});
        try tmp.dir.writeFile(io, .{ .sub_path = name, .data = "contents" });
        const stat = try tmp.dir.statFile(io, name, .{});

        asset.* = try asset_manager.mECSManager.CreateEntity(keep_allocator);
        var file_data = FileMetaData{ .mPathType = .Eng, .mLastModified = stat.mtime, .mSize = stat.size };
        try file_data.mRelPath.print(keep_allocator, ".zig-cache/tmp/{s}/{s}", .{ tmp.sub_path, name });
        _ = try asset_manager.mECSManager.AddComponentSync(engine_context, asset.*, file_data);
    }

    //one file gone, and one whose tracked size is out of date
    const missing = 7;
    const changed = 23;
    try tmp.dir.deleteFile(io, "file7.txt");
    asset_manager.mECSManager.GetComponentMut(FileMetaData, assets[changed]).?.mSize = 1;

    try asset_manager.OnUpdate(engine_context);

    for (assets, 0..) |asset, i| {
        try std.testing.expectEqual(i == missing, asset_manager.mECSManager.HasComponent(PendingDelete, asset));
        try std.testing.expectEqual(@as(u64, "contents".len), asset_manager.mECSManager.GetComponent(FileMetaData, asset).?.mSize);
    }
    try std.testing.expect(asset_manager.mECSManager.GetComponent(FileMetaData, assets[changed]).?.mHash != 0);
}
