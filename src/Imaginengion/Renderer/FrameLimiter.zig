//! Holds rendering to at most a set number of frames a second. A pass of the loop that comes before the next frame is
//! due skips rendering, the same as one that finds no window image free, and the rest of the loop runs as usual.
//! Times are passed in rather than read here, so it can be tested without a clock.
const std = @import("std");

const FrameLimiter = @This();

/// Frames a second, 0 for no limit
mLimit: u32 = 0,
/// When the next frame is due, in nanoseconds. Null until the first frame
mNextFrame: ?i96 = null,

pub fn Init(limit: u32) FrameLimiter {
    return .{ .mLimit = limit };
}

/// Whether a frame may start at `now`
pub fn IsDue(self: FrameLimiter, now: i96) bool {
    if (self.mLimit == 0) return true;
    const next = self.mNextFrame orelse return true;
    return now >= next;
}

/// A frame started at `now`, so the next is due one period on. That is a period after this one was due rather than
/// after `now`, so passes of the loop landing a little late don't drag the rate below the limit. A frame a whole period
/// or more late (a hitch, a breakpoint) starts the schedule over from `now`, rather than rendering a burst to catch up
pub fn FrameStarted(self: *FrameLimiter, now: i96) void {
    if (self.mLimit == 0) return;
    const period: i96 = @divTrunc(std.time.ns_per_s, self.mLimit);
    const due = self.mNextFrame orelse now;
    self.mNextFrame = if (now - due >= period) now + period else due + period;
}
