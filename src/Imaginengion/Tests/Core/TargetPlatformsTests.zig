//! The target platforms and their memory budgets (Core/TargetPlatforms.zig): a new project's one platform, adding,
//! renaming and removing them, which one is the target, the warning when the game goes over a budget, and their
//! settings file. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const TargetPlatforms = @import("../../Core/TargetPlatforms.zig");

const MB: u64 = 1024 * 1024;

test "a new project has one platform, PC, as its target, and the last platform can't be removed" {
    var platforms: TargetPlatforms = .{};
    try std.testing.expectEqual(1, platforms.Count());
    try std.testing.expectEqualStrings("PC", platforms.GetName(platforms.mTarget));
    try std.testing.expect(platforms.Target().mCPUMemoryMB > 0 and platforms.Target().mVideoMemoryMB > 0);
    try std.testing.expectError(error.LastPlatform, platforms.Remove(0));
}

test "platforms are added, renamed and removed, and the target follows the platform it was" {
    var platforms: TargetPlatforms = .{};
    try platforms.Add();
    try platforms.Add();
    try std.testing.expectEqualStrings("Platform 3", platforms.GetName(2));

    platforms.SetName(1, "  Switch 2 ");
    try std.testing.expectEqualStrings("Switch 2", platforms.GetName(1));
    //an empty name is left as it was, a long one cut short
    platforms.SetName(1, "   ");
    try std.testing.expectEqualStrings("Switch 2", platforms.GetName(1));
    platforms.SetName(2, "A name much longer than thirty two bytes");
    try std.testing.expectEqual(TargetPlatforms.MAX_NAME_LEN, platforms.GetName(2).len);

    platforms.SetTarget(2);
    platforms.SetCPUMemoryMB(2, 3000);
    //removing one before the target moves it up with its platform
    try platforms.Remove(0);
    try std.testing.expectEqual(1, platforms.mTarget);
    try std.testing.expectEqual(3000, platforms.Target().mCPUMemoryMB);
    //removing the target makes the one before it the target
    try platforms.Remove(1);
    try std.testing.expectEqualStrings("Switch 2", platforms.GetName(platforms.mTarget));

    for (platforms.Count()..TargetPlatforms.MAX_PLATFORMS) |_| try platforms.Add();
    try std.testing.expectError(error.TooManyPlatforms, platforms.Add());
}

test "going over a budget is found once, until it is back under" {
    var platforms: TargetPlatforms = .{};
    platforms.SetCPUMemoryMB(0, 100);
    platforms.SetVideoMemoryMB(0, 50);

    platforms.Check(.{ .CPU = 90 * MB, .Video = 10 * MB });
    try std.testing.expect(!platforms.mOverCPU);
    try std.testing.expectEqual(90 * MB, platforms.mLastUsage.CPU);

    platforms.Check(.{ .CPU = 120 * MB, .Video = 60 * MB });
    try std.testing.expect(platforms.mOverCPU and platforms.mOverVideo);
    //still over: no new warning, since it already was
    platforms.Check(.{ .CPU = 130 * MB, .Video = 10 * MB });
    try std.testing.expect(platforms.mOverCPU and !platforms.mOverVideo);

    //a new target starts fresh
    try platforms.Add();
    platforms.SetTarget(1);
    try std.testing.expect(!platforms.mOverCPU);
}

test "the platforms are saved to their settings and read back, the target by its name" {
    const engine_context = try std.heap.page_allocator.create(EngineContext);
    defer std.heap.page_allocator.destroy(engine_context);
    engine_context.* = .{};
    defer _ = engine_context._Internal.KeepHeap.deinit();

    var platforms: TargetPlatforms = .{};
    try platforms.Add();
    platforms.SetName(1, "Switch 2");
    platforms.SetCPUMemoryMB(1, 3072);
    platforms.SetVideoMemoryMB(1, 1024);
    platforms.SetTarget(1);

    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    var write_stream: std.json.Stringify = .{ .writer = &out.writer };
    try platforms.SaveProjectSettings(engine_context, &write_stream);

    var loaded: TargetPlatforms = .{};
    var scanner = std.json.Scanner.initCompleteInput(engine_context.Scratch(), out.written());
    defer scanner.deinit();
    try loaded.LoadProjectSettings(engine_context, &scanner);
    try std.testing.expectEqual(2, loaded.Count());
    try std.testing.expectEqualStrings("Switch 2", loaded.GetName(loaded.mTarget));
    try std.testing.expectEqual(3072, loaded.Target().mCPUMemoryMB);
    try std.testing.expectEqual(1024, loaded.Target().mVideoMemoryMB);

    //settings with no platforms leave a new project's
    var scanner_empty = std.json.Scanner.initCompleteInput(engine_context.Scratch(), "{}");
    defer scanner_empty.deinit();
    try loaded.LoadProjectSettings(engine_context, &scanner_empty);
    try std.testing.expectEqual(1, loaded.Count());
    try std.testing.expectEqualStrings("PC", loaded.GetName(0));
}
