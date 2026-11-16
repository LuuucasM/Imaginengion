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
const AudioAsset = Assets.AudioAsset;
const PendingDelete = Assets.PendingDelete;
const EngineFiles = @import("../../../GameBuild/EngineFiles.zig");

/// An EngineContext with just enough set up for the asset manager. No Setup: its default assets
/// need the GPU, and nothing here actually loads an asset.
const TestContext = struct {
    mEngineContext: *EngineContext,

    fn Init() !*TestContext {
        const self = try std.heap.page_allocator.create(TestContext);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
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

        const asset_manager = &engine_context.mAssetManager;
        if (asset_manager._internal.DefaultAudioHandle) |*handle| handle.ReleaseAsset();
        asset_manager.mECSManager.Deinit(engine_context);
        asset_manager.mUUIDToWorldID.deinit(keep_allocator);
        asset_manager.mEventManager.Deinit(keep_allocator);
        asset_manager.mCWDPath.deinit(keep_allocator);

        _ = engine_context._Internal.KeepHeap.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }
};

/// A file asset whose file does not exist, so any attempt to load it errors instead of passing
fn CreateMissingFileAsset(engine_context: *EngineContext) !AssetHandle.Type {
    const asset_manager = &engine_context.mAssetManager;
    const keep_allocator = engine_context.Keep();

    const asset_id = try asset_manager.mECSManager.CreateEntity();
    var file_meta_data = FileMetaData{ .mPathType = .Eng };
    _ = try file_meta_data.mRelPath.print(keep_allocator, "{s}", .{"does/not/exist.ttf"});
    _ = try asset_manager.mECSManager.AddComponentSync(engine_context, asset_id, file_meta_data);
    return asset_id;
}

test "a failed asset hands back the default without loading again" {
    const test_context = try TestContext.Init();
    defer test_context.Deinit();
    const engine_context = test_context.mEngineContext;
    const asset_manager = &engine_context.mAssetManager;

    const asset_id = try CreateMissingFileAsset(engine_context);
    _ = try asset_manager.mECSManager.AddComponentSync(engine_context, asset_id, LoadFailedTag{});

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
    const keep_allocator = engine_context.Keep();

    const asset_id = try CreateMissingFileAsset(engine_context);
    _ = try asset_manager.mECSManager.AddComponentSync(engine_context, asset_id, LoadFailedTag{});

    //what OnUpdate queues when it sees the file's mtime or size change
    try asset_manager.mEventManager.Insert(keep_allocator, .EndOfFrame, .{ .FileUpdate = .{ .mAssetID = asset_id } });
    try asset_manager.ProcessDestroyedAssets(engine_context);

    try std.testing.expect(!asset_manager.mECSManager.HasComponent(LoadFailedTag, asset_id));
    try std.testing.expect(asset_manager.mECSManager.IsActiveEntity(asset_id));

    //no longer short-circuited: it really tries the file now, which here is missing
    try std.testing.expectError(error.FileNotFound, asset_manager.GetAsset(engine_context, TextAsset, asset_id));
}

test "a change to the file marks it changed until the next update clears it" {
    const test_context = try TestContext.Init();
    defer test_context.Deinit();
    const engine_context = test_context.mEngineContext;
    const asset_manager = &engine_context.mAssetManager;
    const keep_allocator = engine_context.Keep();

    const asset_id = try CreateMissingFileAsset(engine_context);
    try std.testing.expect(!asset_manager.AnyFileChanged());

    try asset_manager.mEventManager.Insert(keep_allocator, .EndOfFrame, .{ .FileUpdate = .{ .mAssetID = asset_id } });
    try asset_manager.ProcessDestroyedAssets(engine_context);
    try std.testing.expect(asset_manager.AnyFileChanged());
    try std.testing.expect(asset_manager.FileChanged(asset_id));

    //what the start of OnUpdate does
    try asset_manager.ClearFileChanged(engine_context);
    try std.testing.expect(!asset_manager.AnyFileChanged());
    try std.testing.expect(!asset_manager.FileChanged(asset_id));
}

test "a default is an ordinary asset: a file naming it shares it, and a failed asset hands it back" {
    const test_context = try TestContext.Init();
    defer test_context.Deinit();
    const engine_context = test_context.mEngineContext;
    const asset_manager = &engine_context.mAssetManager;

    //the sound, the one default that needs no GPU
    try asset_manager.HoldDefault(engine_context, AudioAsset, EngineFiles.DEFAULT_SOUND);
    const held = asset_manager._internal.DefaultAudioHandle.?;
    const default_sound = try held.GetAsset(engine_context, AudioAsset);
    try std.testing.expect(default_sound.GetFrameCount() > 0);

    //naming the same file is the same asset, read once
    var named = try asset_manager.GetAssetHandle(engine_context, .{ .File = .{ .rel_path = EngineFiles.DEFAULT_SOUND, .path_type = .Eng } });
    defer named.ReleaseAsset();
    try std.testing.expectEqual(held.mID, named.mID);
    try std.testing.expectEqual(default_sound, try named.GetAsset(engine_context, AudioAsset));

    //an asset that failed gets the held default, not the empty stand-in
    const failed_id = try CreateMissingFileAsset(engine_context);
    _ = try asset_manager.mECSManager.AddComponentSync(engine_context, failed_id, LoadFailedTag{});
    try std.testing.expectEqual(default_sound, try asset_manager.GetAsset(engine_context, AudioAsset, failed_id));
}

test "an asset nothing holds is destroyed after the grace period, unless something takes it up again first" {
    const test_context = try TestContext.Init();
    defer test_context.Deinit();
    const engine_context = test_context.mEngineContext;
    const asset_manager = &engine_context.mAssetManager;
    const source: @import("../../../ECSManagers/AManager.zig").AssetSource = .{ .File = .{ .rel_path = EngineFiles.DEFAULT_SOUND, .path_type = .Eng } };

    var handle = try asset_manager.GetAssetHandle(engine_context, source);
    const asset_id = handle.mID;
    _ = try handle.GetAsset(engine_context, AudioAsset);

    //held: left alone
    try asset_manager.ProcessDestroyedAssets(engine_context);
    try std.testing.expect(!asset_manager.mECSManager.HasComponent(PendingDelete, asset_id));

    //let go of: marked, and taken up again inside the grace period, unmarked
    handle.ReleaseAsset();
    try asset_manager.ProcessDestroyedAssets(engine_context);
    try std.testing.expect(asset_manager.mECSManager.HasComponent(PendingDelete, asset_id));
    var again = try asset_manager.GetAssetHandle(engine_context, source);
    try std.testing.expectEqual(asset_id, again.mID);
    try asset_manager.ProcessDestroyedAssets(engine_context);
    try std.testing.expect(!asset_manager.mECSManager.HasComponent(PendingDelete, asset_id));

    //let go of for longer than the grace period: destroyed, and out of the path map, so naming it again reads it anew
    again.ReleaseAsset();
    try asset_manager.ProcessDestroyedAssets(engine_context);
    asset_manager.mECSManager.GetComponentMut(PendingDelete, asset_id).?.mTime = .zero;
    try asset_manager.ProcessDestroyedAssets(engine_context);
    try std.testing.expect(!asset_manager.mECSManager.IsActiveEntity(asset_id));
    var fresh = try asset_manager.GetAssetHandle(engine_context, source);
    defer fresh.ReleaseAsset();
    try std.testing.expect(!asset_manager.IsLoaded(AudioAsset, fresh.mID));
}
