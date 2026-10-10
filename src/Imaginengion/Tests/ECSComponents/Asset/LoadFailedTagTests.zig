//! LoadFailedTag marks an asset whose last load failed, so GetAsset stops retrying it every frame
//! (a font retried its seconds-long atlas generation every call) until the file changes.
//! Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../../Core/EngineContext.zig");
const Assets = @import("../../../ECSComponents/AComponents.zig");
const LoadFailedTag = Assets.LoadFailedTag;
const FileMetaData = Assets.FileMetaData;
const TextAsset = Assets.TextAsset;
const AssetHandle = @import("../../../ECSObjects/AssetHandle.zig");

/// An EngineContext with just enough set up for the asset manager. No Setup: its default assets
/// need the GPU, and nothing here actually loads an asset.
const TestContext = struct {
    mEngineContext: *EngineContext,

    fn Init() !*TestContext {
        const self = try std.heap.page_allocator.create(TestContext);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
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

/// A file asset whose file does not exist, so any attempt to load it errors instead of passing
fn CreateMissingFileAsset(engine_context: *EngineContext) !AssetHandle.Type {
    const asset_manager = &engine_context.mAssetManager;
    const engine_allocator = engine_context.EngineAllocator();

    const asset_id = try asset_manager.mECSManager.CreateEntity(engine_allocator);
    var file_meta_data = FileMetaData{ .mPathType = .Eng };
    _ = try file_meta_data.mRelPath.print(engine_allocator, "{s}", .{"does/not/exist.ttf"});
    _ = try asset_manager.mECSManager.AddComponent(engine_allocator, asset_id, file_meta_data);
    return asset_id;
}

test "a failed asset hands back the default without loading again" {
    const test_context = try TestContext.Init();
    defer test_context.Deinit();
    const engine_context = test_context.mEngineContext;
    const asset_manager = &engine_context.mAssetManager;

    const asset_id = try CreateMissingFileAsset(engine_context);
    _ = try asset_manager.mECSManager.AddComponent(engine_context.EngineAllocator(), asset_id, LoadFailedTag{});

    //a load would try to open the missing file and error, so getting the default back means it was skipped
    const asset = try asset_manager.GetAsset(engine_context, TextAsset, asset_id);
    try std.testing.expectEqual(&asset_manager._internal.DefaultTextAsset, asset);
    try std.testing.expect(!asset_manager.mECSManager.HasComponent(TextAsset, asset_id));
}

test "a change to the file clears the mark so the next GetAsset tries again" {
    const test_context = try TestContext.Init();
    defer test_context.Deinit();
    const engine_context = test_context.mEngineContext;
    const asset_manager = &engine_context.mAssetManager;
    const engine_allocator = engine_context.EngineAllocator();

    const asset_id = try CreateMissingFileAsset(engine_context);
    _ = try asset_manager.mECSManager.AddComponent(engine_allocator, asset_id, LoadFailedTag{});

    //what OnUpdate queues when it sees the file's mtime or size change
    try asset_manager.mEventManager.Insert(engine_allocator, .EndOfFrame, .{ .FileUpdate = .{ .mAssetID = asset_id } });
    try asset_manager.ProcessDestroyedAssets(engine_context);

    try std.testing.expect(!asset_manager.mECSManager.HasComponent(LoadFailedTag, asset_id));
    try std.testing.expect(asset_manager.mECSManager.IsActiveEntity(asset_id));

    //no longer short-circuited: it really tries the file now, which here is missing
    try std.testing.expectError(error.FileNotFound, asset_manager.GetAsset(engine_context, TextAsset, asset_id));
}
