//! EngineStats (Core/EngineStats.zig): the rate counters behind the Stats panel's Loops/s and FPS, and which frame's
//! stats are kept for the panel. Run with `zig build test-engine`.
const std = @import("std");

const EngineStats = @import("../../Core/EngineStats.zig");
const RateCounter = EngineStats.RateCounter;

//the steps below are powers of two, which add up to exactly a second in floats: 1/60 sixty times falls just short

test "a rate counter works its rate out once a second, from that whole second" {
    var counter: RateCounter = .{};
    //half a second in, nothing worked out yet
    for (0..32) |_| {
        counter.Tick();
        counter.Advance(1.0 / 64.0);
    }
    try std.testing.expectEqual(@as(f32, 0), counter.mRate);

    for (0..32) |_| {
        counter.Tick();
        counter.Advance(1.0 / 64.0);
    }
    try std.testing.expectEqual(@as(f32, 64), counter.mRate);
    //and it starts counting the next second from nothing
    try std.testing.expectEqual(@as(u32, 0), counter.mCount);
}

test "loops a second and frames a second are counted apart" {
    var stats: EngineStats = .{};
    //a second of 512 passes of the loop, only every fourth of which got a window image to draw into
    for (0..512) |i| {
        if (i % 4 == 0) stats.FrameAcquired();
        stats.ResetStats();
        stats.CountLoop(1.0 / 512.0);
    }
    try std.testing.expectEqual(@as(f32, 512), stats.LoopRate.mRate);
    try std.testing.expectEqual(@as(f32, 128), stats.FrameRate.mRate);
}

test "a pass that skipped rendering keeps the last rendered frame's stats" {
    var stats: EngineStats = .{};
    stats.FrameAcquired();
    stats.EditorWorldStats.mRenderStats.OutputGlyphNum = 42;
    stats.ResetStats();
    try std.testing.expectEqual(@as(usize, 42), stats.LastEditorWorldStats.mRenderStats.OutputGlyphNum);

    //no window image this pass, so nothing was drawn and nothing was counted
    stats.ResetStats();
    try std.testing.expectEqual(@as(usize, 42), stats.LastEditorWorldStats.mRenderStats.OutputGlyphNum);
    try std.testing.expectEqual(@as(usize, 0), stats.EditorWorldStats.mRenderStats.OutputGlyphNum);
}
