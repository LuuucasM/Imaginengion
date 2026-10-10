//! GetWorld for every object type: it is the world the object was made in. No window or renderer needed.
//! Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const Player = @import("../../ECSObjects/Player.zig");
const GameContext = @import("../../ECSObjects/GameContext.zig");

test "every object type hands back the world it lives in" {
    const engine_context = try std.heap.page_allocator.create(EngineContext);
    defer std.heap.page_allocator.destroy(engine_context);
    engine_context.* = .{};
    //UUIDs are drawn from the context's Io, which forwards to this
    engine_context._Internal.ThreadedIO = std.Io.Threaded.init(engine_context._Internal.EngineGPA.allocator(), .{
        .concurrent_limit = .nothing,
        .async_limit = .nothing,
    });
    defer _ = engine_context._Internal.EngineGPA.deinit();

    const world = &engine_context.mEditorWorld;
    try world.Init(engine_context.EngineAllocator());
    defer world.Deinit(engine_context);

    const scene = try world.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const entity = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    const player = try world.CreatePlayer(engine_context, Player.DefaultConfig);
    const game_context = try world.CreateGameContext(engine_context, GameContext.DefaultConfig);

    try std.testing.expectEqual(world, entity.GetWorld());
    try std.testing.expectEqual(world, scene.GetWorld());
    try std.testing.expectEqual(world, player.GetWorld());
    try std.testing.expectEqual(world, game_context.GetWorld());
}
