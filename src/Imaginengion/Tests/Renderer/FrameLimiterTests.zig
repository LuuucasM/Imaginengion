//! FrameLimiter: how many frames start a second. No engine needed. Run with `zig build test`.
const std = @import("std");
const FrameLimiter = @import("../../Renderer/FrameLimiter.zig");

const ms: i96 = std.time.ns_per_ms;

/// How many frames start over `duration`, with a pass of the loop every `step`, starting at time 0
fn FramesOver(limiter: *FrameLimiter, duration: i96, step: i96) u32 {
    var frames: u32 = 0;
    var now: i96 = 0;
    while (now < duration) : (now += step) {
        if (limiter.IsDue(now)) {
            limiter.FrameStarted(now);
            frames += 1;
        }
    }
    return frames;
}

test "with no limit every pass of the loop may render" {
    var limiter = FrameLimiter.Init(0);
    try std.testing.expectEqual(@as(u32, 1000), FramesOver(&limiter, 1000 * ms, ms));
}

test "the first frame is due straight away" {
    const limiter = FrameLimiter.Init(60);
    try std.testing.expect(limiter.IsDue(12345 * ms));
}

test "a frame is not due again until a period after the last" {
    var limiter = FrameLimiter.Init(100);
    limiter.FrameStarted(0);
    try std.testing.expect(!limiter.IsDue(9 * ms));
    try std.testing.expect(limiter.IsDue(10 * ms));
}

test "the limit holds when the loop runs much faster" {
    var limiter = FrameLimiter.Init(144);
    try std.testing.expectEqual(@as(u32, 144), FramesOver(&limiter, std.time.ns_per_s, std.time.ns_per_us * 50));
}

test "passes landing a little late don't drag the rate below the limit" {
    //a pass every 3 ms never lands exactly on the 10 ms period, so each frame starts up to 2 ms late. Scheduling from
    //when a frame started rather than when it was due would lose a few frames a second here
    var limiter = FrameLimiter.Init(100);
    try std.testing.expectEqual(@as(u32, 100), FramesOver(&limiter, std.time.ns_per_s, 3 * ms));
}

test "a frame that couldn't start leaves the next one due" {
    //IsDue alone doesn't use up the frame, so a pass that finds no window image free can try again on the next one
    var limiter = FrameLimiter.Init(100);
    limiter.FrameStarted(0);
    try std.testing.expect(limiter.IsDue(10 * ms));
    try std.testing.expect(limiter.IsDue(11 * ms));
    limiter.FrameStarted(11 * ms);
    try std.testing.expect(!limiter.IsDue(19 * ms));
    try std.testing.expect(limiter.IsDue(20 * ms));
}

test "after a long stall it starts over rather than rendering a burst to catch up" {
    var limiter = FrameLimiter.Init(100);
    limiter.FrameStarted(0);
    //half a second with no pass of the loop at all
    limiter.FrameStarted(500 * ms);
    try std.testing.expect(!limiter.IsDue(505 * ms));
    try std.testing.expect(limiter.IsDue(510 * ms));
}
