//! The game's own share of memory (Core/GameMemory.zig): its assets are those its objects hold handles to, an asset only
//! the editor holds isn't one, and the totals the editor and a game set against a budget (TargetPlatforms.EditorUsage,
//! GameUsage): the parts plus the engine's recorded baseline, or the whole with the baseline as what is beyond the
//! parts. No GPU needed: the asset is a sound. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const GameMemory = @import("../../Core/GameMemory.zig");
const TargetPlatforms = @import("../../Core/TargetPlatforms.zig");
const EngineFiles = @import("../../GameBuild/EngineFiles.zig");
const Assets = @import("../../ECSComponents/AComponents.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const AudioComponent = @import("../../ECSComponents/EComponents.zig").AudioComponent;

test "the game's assets are those its objects hold, not the editor's own" {
    const engine_context = try std.heap.page_allocator.create(EngineContext);
    defer std.heap.page_allocator.destroy(engine_context);
    engine_context.* = .{};
    engine_context._Internal.ThreadPool = std.Io.Threaded.init(engine_context._Internal.KeepHeap.allocator(), .{ .concurrent_limit = .nothing, .async_limit = .nothing });
    const asset_manager = &engine_context.mAssetManager;
    try asset_manager.Init(engine_context);
    try engine_context.mGameWorld.Init(engine_context);
    defer {
        engine_context.mGameWorld.Deinit(engine_context);
        const keep_allocator = engine_context.Keep();
        asset_manager.mECSManager.Deinit(engine_context);
        asset_manager.mUUIDToWorldID.deinit(keep_allocator);
        asset_manager.mEventManager.Deinit(keep_allocator);
        asset_manager.mCWDPath.deinit(keep_allocator);
        _ = engine_context._Internal.KeepHeap.deinit();
    }
    const world = &engine_context.mGameWorld;

    //a sound only the editor holds: not the game's
    var editors = try asset_manager.GetAssetHandle(engine_context, .{ .File = .{ .rel_path = EngineFiles.DEFAULT_SOUND, .path_type = .Eng } });
    defer editors.ReleaseAsset();
    const sound = try editors.GetAsset(engine_context, Assets.AudioAsset);
    const decoded = sound.GetSamples().len * @sizeOf(f32);
    const before = try GameMemory.MeasureParts(engine_context, world);
    try std.testing.expectEqual(0, before.AssetsCPU);
    try std.testing.expect(before.WorldCPU > 0);

    //the same sound on one of the game's entities: the game's, once however many hold it
    const scene = try world.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    for (0..2) |_| {
        const entity = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
        var handle = editors;
        handle.RetainAsset();
        _ = try entity.AddComponent(engine_context, AudioComponent{ .mAudioAsset = handle });
    }
    const after = try GameMemory.MeasureParts(engine_context, world);
    try std.testing.expectEqual(decoded, after.AssetsCPU);
    try std.testing.expectEqual(after.WorldCPU + after.ObjectsCPU + after.AssetsCPU, after.CPU());
}

test "the editor adds the engine's recorded baseline to the game's parts, and a game finds it as the rest" {
    var platforms: TargetPlatforms = .{};
    const parts = GameMemory.Parts{ .WorldCPU = 100, .ObjectsCPU = 20, .AssetsCPU = 30, .WorldVideo = 7, .AssetsVideo = 40 };

    //nothing recorded yet: only the parts, and it says so
    const unrecorded = platforms.EditorUsage(parts);
    try std.testing.expectEqual(150, unrecorded.CPU);
    try std.testing.expectEqual(47, unrecorded.Video);
    try std.testing.expect(unrecorded.Baseline == null);

    platforms.mRecorded = .{ .CPU = 1000, .Video = 500 };
    const recorded = platforms.EditorUsage(parts);
    try std.testing.expectEqual(1150, recorded.CPU);
    try std.testing.expectEqual(547, recorded.Video);
    try std.testing.expectEqual(1000, recorded.Baseline.?.CPU);
}

test "the date a baseline was measured is written as YYYY-MM-DD" {
    var buffer: [10]u8 = undefined;
    const today = GameMemory.Today(std.testing.io, &buffer);
    try std.testing.expectEqual(10, today.len);
    try std.testing.expectEqual('-', today[4]);
    try std.testing.expectEqual('-', today[7]);
    try std.testing.expect(std.mem.startsWith(u8, today, "20"));
}
