//! What each owner of memory has taken (Allocators.Counts): a world's Keep and Scratch are counted on that world and
//! never on the engine or another world, Scratch counts roll over at the end of a pass, and play's copy of the game
//! world is the Simulate world's. No window or renderer needed. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Allocators = @import("../../Core/Allocators.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const NameComponent = @import("../../ECSComponents/EComponents.zig").NameComponent;
const StatsPanel = @import("../../EditorPanels/StatsPanel.zig");

fn NewContext() !*EngineContext {
    const engine_context = try std.heap.page_allocator.create(EngineContext);
    engine_context.* = .{};
    //UUIDs are drawn from the context's Io, which forwards to this
    engine_context._Internal.ThreadPool = std.Io.Threaded.init(engine_context._Internal.KeepHeap.allocator(), .{
        .concurrent_limit = .nothing,
        .async_limit = .nothing,
    });
    try engine_context.mGameWorld.Init(engine_context);
    try engine_context.mSimulateWorld.Init(engine_context);
    return engine_context;
}

fn FreeContext(engine_context: *EngineContext) void {
    engine_context.mSimulateWorld.Deinit(engine_context);
    engine_context.mGameWorld.Deinit(engine_context);
    engine_context._Internal.ThreadScratchArenas.Deinit();
    engine_context._Internal.ScratchArena.deinit();
    _ = engine_context._Internal.KeepHeap.deinit();
    std.heap.page_allocator.destroy(engine_context);
}

fn CountsOf(counts: *const Allocators.Counts) Allocators.Counts.Snapshot {
    return counts.Read();
}

test "a world's Keep is counted on that world only, and goes back down when freed" {
    const engine_context = try NewContext();
    defer FreeContext(engine_context);
    const game = &engine_context.mGameWorld;

    const game_before = CountsOf(&game.mAllocators.mCounts);
    const simulate_before = CountsOf(&engine_context.mSimulateWorld.mAllocators.mCounts);
    const engine_before = CountsOf(&engine_context._Internal.Counts);

    const bytes = try game.Keep().alloc(u8, 100);
    const held = CountsOf(&game.mAllocators.mCounts);
    try std.testing.expectEqual(game_before.KeepBytes + 100, held.KeepBytes);
    try std.testing.expectEqual(game_before.KeepAllocs + 1, held.KeepAllocs);
    try std.testing.expect(held.KeepPeak >= held.KeepBytes);
    //nothing on anyone else
    try std.testing.expectEqual(simulate_before, CountsOf(&engine_context.mSimulateWorld.mAllocators.mCounts));
    try std.testing.expectEqual(engine_before, CountsOf(&engine_context._Internal.Counts));

    //growing it in place or by moving it counts the difference
    const grown = try game.Keep().realloc(bytes, 300);
    try std.testing.expectEqual(game_before.KeepBytes + 300, CountsOf(&game.mAllocators.mCounts).KeepBytes);

    game.Keep().free(grown);
    const freed = CountsOf(&game.mAllocators.mCounts);
    try std.testing.expectEqual(game_before.KeepBytes, freed.KeepBytes);
    try std.testing.expectEqual(game_before.KeepAllocs, freed.KeepAllocs);
    //the peak stays where it got to
    try std.testing.expect(freed.KeepPeak >= game_before.KeepBytes + 300);
}

test "Scratch is counted for the pass, and becomes the last pass's when it ends" {
    const engine_context = try NewContext();
    defer FreeContext(engine_context);
    const game = &engine_context.mGameWorld;
    engine_context.EndScratchPass();

    _ = try game.Scratch().alloc(u8, 64);
    _ = try game.Scratch().alloc(u8, 36);
    _ = try engine_context.Scratch().alloc(u8, 8);
    //nothing shows until the pass ends
    try std.testing.expectEqual(@as(i64, 0), CountsOf(&game.mAllocators.mCounts).ScratchLast);

    engine_context.EndScratchPass();
    try std.testing.expectEqual(@as(i64, 100), CountsOf(&game.mAllocators.mCounts).ScratchLast);
    try std.testing.expectEqual(@as(i64, 8), CountsOf(&engine_context._Internal.Counts).ScratchLast);
    try std.testing.expectEqual(@as(i64, 0), CountsOf(&engine_context.mSimulateWorld.mAllocators.mCounts).ScratchLast);

    //a pass that takes nothing: the last is nothing, the peak stays
    engine_context.EndScratchPass();
    const quiet = CountsOf(&game.mAllocators.mCounts);
    try std.testing.expectEqual(@as(i64, 0), quiet.ScratchLast);
    try std.testing.expectEqual(@as(i64, 100), quiet.ScratchPeak);
}

test "play's copy of the game world is the Simulate world's memory, and none of the game world's" {
    const engine_context = try NewContext();
    defer FreeContext(engine_context);
    const game = &engine_context.mGameWorld;
    const simulate = &engine_context.mSimulateWorld;

    const scene = try game.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    for (0..20) |_| {
        const entity = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
        try entity.SetName(engine_context, "A name long enough to be its own allocation");
    }

    const game_before = CountsOf(&game.mAllocators.mCounts);
    const simulate_before = CountsOf(&simulate.mAllocators.mCounts);
    try game.Copy(engine_context, simulate);
    try std.testing.expectEqual(game_before.KeepBytes, CountsOf(&game.mAllocators.mCounts).KeepBytes);
    const copied = CountsOf(&simulate.mAllocators.mCounts);
    try std.testing.expect(copied.KeepBytes > simulate_before.KeepBytes);

    //stopping frees it from the Simulate world, through the same world that took it
    simulate.clearAndFree(engine_context, .All);
    const stopped = CountsOf(&simulate.mAllocators.mCounts);
    try std.testing.expect(stopped.KeepBytes < copied.KeepBytes);
    try std.testing.expect(stopped.KeepBytes >= 0);
    try std.testing.expectEqual(game_before.KeepBytes, CountsOf(&game.mAllocators.mCounts).KeepBytes);
}

test "byte counts are shown in the largest unit they fill" {
    var buffer: [32]u8 = undefined;
    try std.testing.expectEqualStrings("12 B", try std.fmt.bufPrint(&buffer, "{f}", .{StatsPanel.Bytes{ .mBytes = 12 }}));
    try std.testing.expectEqualStrings("1.5 KB", try std.fmt.bufPrint(&buffer, "{f}", .{StatsPanel.Bytes{ .mBytes = 1536 }}));
    try std.testing.expectEqualStrings("3.0 MB", try std.fmt.bufPrint(&buffer, "{f}", .{StatsPanel.Bytes{ .mBytes = 3 * 1024 * 1024 }}));
    try std.testing.expectEqualStrings("-2.0 KB", try std.fmt.bufPrint(&buffer, "{f}", .{StatsPanel.Bytes{ .mBytes = -2048 }}));
}

test "a GPU texture's size is its texels for every level, layer and sample" {
    const GPUAllocator = @import("../../Core/GPUAllocator.zig");
    const sdl = @import("../../Core/CImports.zig").sdl;
    var info = std.mem.zeroes(sdl.SDL_GPUTextureCreateInfo);
    info.type = sdl.SDL_GPU_TEXTURETYPE_2D;
    info.format = sdl.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM;
    info.width = 64;
    info.height = 32;
    info.layer_count_or_depth = 1;
    info.num_levels = 1;
    info.sample_count = sdl.SDL_GPU_SAMPLECOUNT_1;
    try std.testing.expectEqual(@as(u64, 64 * 32 * 4), GPUAllocator.TextureBytes(&info));

    //every level is half as wide and high, down to 1
    info.num_levels = 3;
    try std.testing.expectEqual(@as(u64, (64 * 32 + 32 * 16 + 16 * 8) * 4), GPUAllocator.TextureBytes(&info));

    //an array's layers and each sample count too
    info.num_levels = 1;
    info.type = sdl.SDL_GPU_TEXTURETYPE_2D_ARRAY;
    info.layer_count_or_depth = 3;
    info.sample_count = sdl.SDL_GPU_SAMPLECOUNT_4;
    try std.testing.expectEqual(@as(u64, 64 * 32 * 4 * 3 * 4), GPUAllocator.TextureBytes(&info));
}

test "nothing on the GPU to start with, for any owner" {
    const GPUAllocator = @import("../../Core/GPUAllocator.zig");
    var gpu: GPUAllocator = .{};
    for (0..GPUAllocator.OWNER_COUNT) |owner| {
        try std.testing.expectEqual(GPUAllocator.Counts{}, gpu.CountsOf(@intCast(owner)));
    }
    gpu.Deinit(std.testing.allocator);
}
