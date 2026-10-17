//! The collision layers' names (Physics/CollisionLayers.zig): a new project's are the layers' numbers, a rename is kept
//! tidy (emptied, too long), and they are saved with the project's settings and read back the way opening one does.
//! Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const CollisionLayers = @import("../../Physics/CollisionLayers.zig");

fn NewEngineContext() !*EngineContext {
    const engine_context = try std.heap.page_allocator.create(EngineContext);
    engine_context.* = .{};
    return engine_context;
}

fn FreeEngineContext(engine_context: *EngineContext) void {
    _ = engine_context._Internal.EngineGPA.deinit();
    std.heap.page_allocator.destroy(engine_context);
}

test "a new project's layers are named by their numbers, and a rename is kept until it is emptied" {
    var layers: CollisionLayers = .{};
    try std.testing.expectEqualStrings("1", layers.GetName(0));
    try std.testing.expectEqualStrings("32", layers.GetName(CollisionLayers.COUNT - 1));

    const version = layers.mVersion;
    layers.SetName(2, "  Enemy ");
    try std.testing.expectEqualStrings("Enemy", layers.GetName(2));
    try std.testing.expect(layers.mVersion != version);

    //the same name again isn't a change
    const renamed = layers.mVersion;
    layers.SetName(2, "Enemy");
    try std.testing.expectEqual(renamed, layers.mVersion);

    layers.SetName(2, "   ");
    try std.testing.expectEqualStrings("3", layers.GetName(2));
}

test "a name too long is cut short, never part way through a character" {
    var layers: CollisionLayers = .{};
    const long: [40]u8 = @splat('a');
    layers.SetName(0, &long);
    try std.testing.expectEqual(@as(usize, CollisionLayers.MAX_NAME_LEN), layers.GetName(0).len);

    //31 bytes, then a 2 byte character that would end past the 32nd
    const b31: [31]u8 = @splat('b');
    const split = b31 ++ "é".*;
    layers.SetName(1, &split);
    try std.testing.expectEqualStrings(&b31, layers.GetName(1));
}

test "the names are saved with the project's settings and read back, a missing one as its number" {
    const engine_context = try NewEngineContext();
    defer FreeEngineContext(engine_context);
    const layers = &engine_context.mCollisionLayers;
    layers.SetName(0, "Player");
    layers.SetName(4, "Pickup");

    var out: std.Io.Writer.Allocating = .init(engine_context.FrameAllocator());
    var write_stream: std.json.Stringify = .{ .writer = &out.writer };
    try layers.SaveProjectSettings(engine_context, &write_stream);

    try layers.ResetProjectSettings(engine_context);
    try std.testing.expectEqualStrings("1", layers.GetName(0));

    var scanner = std.json.Scanner.initCompleteInput(engine_context.FrameAllocator(), out.written());
    defer scanner.deinit();
    try layers.LoadProjectSettings(engine_context, &scanner);
    try std.testing.expectEqualStrings("Player", layers.GetName(0));
    try std.testing.expectEqualStrings("Pickup", layers.GetName(4));
    try std.testing.expectEqualStrings("2", layers.GetName(1));

    //settings with fewer names than layers (hand edited) leave the rest at their numbers
    var short_scanner = std.json.Scanner.initCompleteInput(engine_context.FrameAllocator(), "{\"Names\":[\"Wall\"]}");
    defer short_scanner.deinit();
    try layers.LoadProjectSettings(engine_context, &short_scanner);
    try std.testing.expectEqualStrings("Wall", layers.GetName(0));
    try std.testing.expectEqualStrings("5", layers.GetName(4));
}
