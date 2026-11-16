//! What each owner of memory has taken (Allocators.Counts): a world's Keep and Scratch are counted on that world and
//! never on the engine or another world, Scratch counts roll over at the end of a pass, and play's copy of the game
//! world is the Simulate world's. No window or renderer needed. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Allocators = @import("../../Core/Allocators.zig");
const CAllocators = @import("../../Core/CAllocators.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const NameComponent = @import("../../ECSComponents/EComponents.zig").NameComponent;
const StatsPanel = @import("../../EditorPanels/StatsPanel.zig");
const WorldManager = @import("../../Core/WorldManager.zig");

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

    const game_before = CountsOf(&game.mMemory.mCounts);
    const simulate_before = CountsOf(&engine_context.mSimulateWorld.mMemory.mCounts);
    const engine_before = CountsOf(&engine_context._Internal.Memory.mCounts);

    const bytes = try game.Keep().alloc(u8, 100);
    const held = CountsOf(&game.mMemory.mCounts);
    try std.testing.expectEqual(game_before.KeepBytes + 100, held.KeepBytes);
    try std.testing.expectEqual(game_before.KeepAllocs + 1, held.KeepAllocs);
    try std.testing.expect(held.KeepPeak >= held.KeepBytes);
    //nothing on anyone else
    try std.testing.expectEqual(simulate_before, CountsOf(&engine_context.mSimulateWorld.mMemory.mCounts));
    try std.testing.expectEqual(engine_before, CountsOf(&engine_context._Internal.Memory.mCounts));

    //growing it in place or by moving it counts the difference
    const grown = try game.Keep().realloc(bytes, 300);
    try std.testing.expectEqual(game_before.KeepBytes + 300, CountsOf(&game.mMemory.mCounts).KeepBytes);

    game.Keep().free(grown);
    const freed = CountsOf(&game.mMemory.mCounts);
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
    try std.testing.expectEqual(@as(i64, 0), CountsOf(&game.mMemory.mCounts).ScratchLast);

    engine_context.EndScratchPass();
    try std.testing.expectEqual(@as(i64, 100), CountsOf(&game.mMemory.mCounts).ScratchLast);
    try std.testing.expectEqual(@as(i64, 8), CountsOf(&engine_context._Internal.Memory.mCounts).ScratchLast);
    try std.testing.expectEqual(@as(i64, 0), CountsOf(&engine_context.mSimulateWorld.mMemory.mCounts).ScratchLast);

    //a pass that takes nothing: the last is nothing, the peak stays
    engine_context.EndScratchPass();
    const quiet = CountsOf(&game.mMemory.mCounts);
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

    //what is under each world's node counts as the world's: the copy goes into the Simulate world's ECSs
    const game_before = game.mMemory.Totals();
    const simulate_before = simulate.mMemory.Totals();
    try game.Copy(engine_context, simulate);
    try std.testing.expectEqual(game_before.Held, game.mMemory.Totals().Held);
    const copied = simulate.mMemory.Totals();
    try std.testing.expect(copied.Held > simulate_before.Held);

    //stopping frees it from the Simulate world, through the same world that took it
    simulate.clearAndFree(engine_context, .All);
    const stopped = simulate.mMemory.Totals();
    try std.testing.expect(stopped.Held < copied.Held);
    try std.testing.expect(stopped.Held >= 0);
    try std.testing.expectEqual(game_before.Held, game.mMemory.Totals().Held);
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

test "the memory tree: worlds under the engine, their ECSs under them, each ECS's component arrays under it" {
    const engine_context = try NewContext();
    defer FreeContext(engine_context);
    const engine_node = &engine_context._Internal.Memory;
    const game = &engine_context.mGameWorld;

    //the worlds made, in the order they were
    var worlds = engine_node.Children();
    try std.testing.expectEqual(&game.mMemory, worlds.next().?);
    try std.testing.expectEqual(&engine_context.mSimulateWorld.mMemory, worlds.next().?);
    try std.testing.expectEqualStrings("Game", game.mMemory.mName);
    try std.testing.expectEqualStrings("Playing", engine_context.mSimulateWorld.mMemory.mName);

    //the four ECSs, and each of their component arrays
    var ecs_count: usize = 0;
    var ecss = game.mMemory.Children();
    while (ecss.next()) |ecs| : (ecs_count += 1) {
        try std.testing.expect(ecs.mFirstChild != null);
        try std.testing.expectEqual(&game.mMemory, ecs.mParent.?);
    }
    try std.testing.expectEqual(@as(usize, 4), ecs_count);
    const entity_ecs = &game.mEManager.mECSManager.mMemory;
    try std.testing.expectEqualStrings("EntityECS", entity_ecs.mName);

    //a component's memory is its array's, and so its ECS's and its world's
    const scene = try game.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const before = game.mMemory.Totals();
    const world_own_before = CountsOf(&game.mMemory.mCounts).KeepBytes;
    const entity_before = entity_ecs.Totals();
    const entity = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    try entity.SetName(engine_context, "A name long enough to be its own allocation");
    try std.testing.expect(entity_ecs.Totals().Held > entity_before.Held);
    try std.testing.expect(game.mMemory.Totals().Held > before.Held);
    //and none of it is the world's own: it all went through the nodes under it
    try std.testing.expectEqual(world_own_before, CountsOf(&game.mMemory.mCounts).KeepBytes);

    //an ECS is inside its world by value, so its bytes are its own size and not the world's too
    try std.testing.expectEqual(@as(usize, @sizeOf(WorldManager)) - EcsSizes(game), game.mMemory.mSize);
}

fn EcsSizes(world: *WorldManager) usize {
    var total: usize = 0;
    var ecss = world.mMemory.Children();
    while (ecss.next()) |ecs| total += ecs.mSize;
    return total;
}

test "a world's node leaves the tree with it, and gives its size back" {
    const engine_context = try std.heap.page_allocator.create(EngineContext);
    defer std.heap.page_allocator.destroy(engine_context);
    engine_context.* = .{};
    defer _ = engine_context._Internal.KeepHeap.deinit();
    const engine_node = &engine_context._Internal.Memory;
    engine_node.mSize = @sizeOf(EngineContext);

    try engine_context.mGameWorld.Init(engine_context);
    try std.testing.expectEqual(@as(usize, @sizeOf(EngineContext) - @sizeOf(WorldManager)), engine_node.mSize);
    try std.testing.expect(engine_node.mFirstChild != null);

    engine_context.mGameWorld.Deinit(engine_context);
    try std.testing.expect(engine_node.mFirstChild == null);
    try std.testing.expectEqual(@as(usize, @sizeOf(EngineContext)), engine_node.mSize);
}

fn ChildNamed(node: *Allocators.MemoryNode, name: []const u8) ?*Allocators.MemoryNode {
    var children = node.Children();
    while (children.next()) |child| {
        if (std.mem.eql(u8, child.mName, name)) return child;
    }
    return null;
}

/// Fails when memory was taken through one node and freed through another: that node's own count goes below nothing
fn ExpectNoneBelowNothing(node: *Allocators.MemoryNode) !void {
    const own = node.mCounts.Read();
    if (own.KeepBytes < 0 or own.KeepAllocs < 0) {
        std.debug.print("{s} holds {d} bytes in {d} allocations\n", .{ node.mName, own.KeepBytes, own.KeepAllocs });
        return error.TakenAndFreedThroughDifferentNodes;
    }
    var children = node.Children();
    while (children.next()) |child| try ExpectNoneBelowNothing(child);
}

test "a component's memory is taken and freed through the same node: its array's" {
    const engine_context = try NewContext();
    defer FreeContext(engine_context);
    const game = &engine_context.mGameWorld;
    const simulate = &engine_context.mSimulateWorld;

    const TextComponent = @import("../../ECSComponents/EComponents.zig").TextComponent;
    const scene = try game.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    for (0..10) |_| {
        const entity = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
        try entity.SetName(engine_context, "A name long enough to be its own allocation");
        const text = try entity.AddComponent(engine_context, TextComponent{});
        try text.SetText(entity.KeepFor(TextComponent), "Some text, also long enough to be its own allocation");
    }
    //a name is its NameComponent array's, held there and not on the ECS
    const name_array = ChildNamed(&game.mEManager.mECSManager.mMemory, NameComponent.Name).?;
    try std.testing.expect(name_array.mCounts.Read().KeepBytes > 0);
    try ExpectNoneBelowNothing(&engine_context._Internal.Memory);

    //play's copy clones every component into the Simulate world's arrays, and stopping frees them all through those
    try game.Copy(engine_context, simulate);
    try ExpectNoneBelowNothing(&engine_context._Internal.Memory);
    simulate.clearAndFree(engine_context, .All);
    try ExpectNoneBelowNothing(&engine_context._Internal.Memory);
    var ecss = simulate.mMemory.Children();
    while (ecss.next()) |ecs| {
        var arrays = ecs.Children();
        while (arrays.next()) |array| try std.testing.expectEqual(@as(i64, 0), array.mCounts.Read().KeepBytes);
    }
}

test "a C library's memory is counted on its node as it takes, grows, shrinks and frees it" {
    //called straight, not through the library: swapping its real functions in a test could free C's memory here
    const Stb = CAllocators.Functions(.StbImage);
    const counts = &CAllocators.gNodes.getPtr(.StbImage).mCounts;
    const before = counts.Read();

    const memory: [*]u8 = @ptrCast(Stb.Malloc(100).?);
    try std.testing.expectEqual(0, @intFromPtr(memory) % 16);
    @memset(memory[0..100], 7);
    try std.testing.expectEqual(before.KeepBytes + 100, counts.Read().KeepBytes);
    try std.testing.expectEqual(before.KeepAllocs + 1, counts.Read().KeepAllocs);

    //what fits is kept as it grows and shrinks
    const grown: [*]u8 = @ptrCast(Stb.Realloc(memory, 5000).?);
    try std.testing.expectEqual(7, grown[99]);
    try std.testing.expectEqual(before.KeepBytes + 5000, counts.Read().KeepBytes);
    const shrunk: [*]u8 = @ptrCast(Stb.Realloc(grown, 10).?);
    try std.testing.expectEqual(7, shrunk[9]);
    try std.testing.expectEqual(before.KeepBytes + 10, counts.Read().KeepBytes);

    //calloc's is zeroed, and realloc of nothing is malloc
    const zeroed: [*]u8 = @ptrCast(Stb.Calloc(4, 8).?);
    try std.testing.expect(std.mem.allEqual(u8, zeroed[0..32], 0));
    const fresh = Stb.Realloc(null, 3).?;
    try std.testing.expectEqual(before.KeepBytes + 10 + 32 + 3, counts.Read().KeepBytes);

    Stb.Free(shrunk);
    Stb.Free(zeroed);
    Stb.Free(fresh);
    Stb.Free(null);
    try std.testing.expectEqual(before.KeepBytes, counts.Read().KeepBytes);
    try std.testing.expectEqual(before.KeepAllocs, counts.Read().KeepAllocs);
    try std.testing.expect(counts.Read().KeepPeak >= before.KeepBytes + 5000);
    //the other libraries' are left alone
    try std.testing.expectEqual(0, CAllocators.gNodes.getPtr(.MiniAudio).mCounts.Read().KeepAllocs);
}
