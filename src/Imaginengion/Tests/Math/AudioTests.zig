const std = @import("std");
const AudioMath = @import("../../Math/Audio.zig");

//mono, so each frame is one sample and expected values read straight off
const source = [_]f32{ 0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0 };

test "pitch 1 reproduces the source exactly" {
    var out: [8]f32 = undefined;
    var cursor: f64 = 0.0;

    try std.testing.expectEqual(8, AudioMath.Read(1, &source, &out, &cursor, 1.0, false));
    try std.testing.expectEqualSlices(f32, &source, &out);
    try std.testing.expectEqual(8.0, cursor);
}

test "pitch 2 takes every other frame" {
    var out: [4]f32 = undefined;
    var cursor: f64 = 0.0;

    try std.testing.expectEqual(4, AudioMath.Read(1, &source, &out, &cursor, 2.0, false));
    try std.testing.expectEqualSlices(f32, &.{ 0.0, 2.0, 4.0, 6.0 }, &out);
}

test "pitch 0.5 blends halfway between frames" {
    var out: [6]f32 = undefined;
    var cursor: f64 = 0.0;

    try std.testing.expectEqual(6, AudioMath.Read(1, &source, &out, &cursor, 0.5, false));
    try std.testing.expectEqualSlices(f32, &.{ 0.0, 0.5, 1.0, 1.5, 2.0, 2.5 }, &out);
}

test "each channel is blended on its own" {
    //left counts up, right counts down
    const stereo = [_]f32{ 0.0, 10.0, 2.0, 8.0, 4.0, 6.0 };
    var out: [4]f32 = undefined;
    var cursor: f64 = 0.5;

    try std.testing.expectEqual(2, AudioMath.Read(2, &stereo, &out, &cursor, 1.0, false));
    try std.testing.expectEqualSlices(f32, &.{ 1.0, 9.0, 3.0, 7.0 }, &out);
}

test "without looping, reading past the end returns fewer frames" {
    var out: [12]f32 = undefined;
    var cursor: f64 = 5.0;

    try std.testing.expectEqual(3, AudioMath.Read(1, &source, &out, &cursor, 1.0, false));
    try std.testing.expectEqualSlices(f32, &.{ 5.0, 6.0, 7.0 }, out[0..3]);

    //and nothing at all once it is done
    try std.testing.expectEqual(0, AudioMath.Read(1, &source, &out, &cursor, 1.0, false));
}

test "the last frame is held rather than blended into silence when not looping" {
    var out: [1]f32 = undefined;
    var cursor: f64 = 7.5;

    try std.testing.expectEqual(1, AudioMath.Read(1, &source, &out, &cursor, 1.0, false));
    try std.testing.expectEqual(7.0, out[0]);
}

test "looping wraps to the start and blends across the loop point" {
    var out: [4]f32 = undefined;
    var cursor: f64 = 6.5;

    //6.5 and 7.5 sit between frames; 7.5 blends the last frame into the first
    try std.testing.expectEqual(4, AudioMath.Read(1, &source, &out, &cursor, 1.0, true));
    try std.testing.expectEqualSlices(f32, &.{ 6.5, 3.5, 0.5, 1.5 }, &out);
}

test "a loop keeps filling however short the sound" {
    const short = [_]f32{ 1.0, 2.0 };
    var out: [7]f32 = undefined;
    var cursor: f64 = 0.0;

    try std.testing.expectEqual(7, AudioMath.Read(1, &short, &out, &cursor, 1.0, true));
    try std.testing.expectEqualSlices(f32, &.{ 1.0, 2.0, 1.0, 2.0, 1.0, 2.0, 1.0 }, &out);
}

test "a pitch that steps past a short loop more than once still wraps correctly" {
    const short = [_]f32{ 0.0, 1.0, 2.0 };
    var out: [3]f32 = undefined;
    var cursor: f64 = 0.0;

    //steps of 7 frames on a 3 frame loop land on 0, 7 % 3 = 1, 8 % 3 = 2
    try std.testing.expectEqual(3, AudioMath.Read(1, &short, &out, &cursor, 7.0, true));
    try std.testing.expectEqualSlices(f32, &.{ 0.0, 1.0, 2.0 }, &out);
}

test "reading in two calls gives the same result as reading in one" {
    const pitch: f32 = 0.37;

    var whole: [16]f32 = undefined;
    var whole_cursor: f64 = 0.0;
    _ = AudioMath.Read(1, &source, &whole, &whole_cursor, pitch, true);

    var split: [16]f32 = undefined;
    var split_cursor: f64 = 0.0;
    _ = AudioMath.Read(1, &source, split[0..9], &split_cursor, pitch, true);
    _ = AudioMath.Read(1, &source, split[9..], &split_cursor, pitch, true);

    try std.testing.expectEqualSlices(f32, &whole, &split);
    try std.testing.expectEqual(whole_cursor, split_cursor);
}

test "pitch is clamped so a voice can never stop moving" {
    var out: [2]f32 = undefined;
    var cursor: f64 = 0.0;

    _ = AudioMath.Read(1, &source, &out, &cursor, 0.0, false);
    try std.testing.expect(cursor > 0.0);

    cursor = 0.0;
    _ = AudioMath.Read(1, &source, &out, &cursor, -3.0, false);
    try std.testing.expect(cursor > 0.0);
}

test "an empty sound reads nothing" {
    var out: [4]f32 = undefined;
    var cursor: f64 = 0.0;

    const empty = [_]f32{};
    try std.testing.expectEqual(0, AudioMath.Read(1, &empty, &out, &cursor, 1.0, true));
}

test "a ramp starts just past from and lands on to" {
    var samples = [_]f32{ 1.0, 1.0, 1.0, 1.0 };
    AudioMath.ApplyRamp(1, &samples, 0.0, 1.0);
    try std.testing.expectEqualSlices(f32, &.{ 0.25, 0.5, 0.75, 1.0 }, &samples);
}

test "a ramp scales every channel of a frame by the same gain" {
    var samples = [_]f32{ 1.0, 2.0, 1.0, 2.0 };
    AudioMath.ApplyRamp(2, &samples, 1.0, 0.0);
    try std.testing.expectEqualSlices(f32, &.{ 0.5, 1.0, 0.0, 0.0 }, &samples);
}

test "a ramp with no change is a plain gain" {
    var samples = [_]f32{ 1.0, -2.0, 4.0 };
    AudioMath.ApplyRamp(1, &samples, 0.5, 0.5);
    try std.testing.expectEqualSlices(f32, &.{ 0.5, -1.0, 2.0 }, &samples);
}

test "a fade steps down to silence and stays there" {
    var samples = [_]f32{ 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 };
    var frames_left: u32 = 4;

    try std.testing.expectEqual(4, AudioMath.ApplyFade(1, &samples, &frames_left, 4));
    try std.testing.expectEqualSlices(f32, &.{ 1.0, 0.75, 0.5, 0.25, 0.0, 0.0 }, &samples);
    try std.testing.expectEqual(0, frames_left);
}

test "a fade split across calls matches one continuous fade" {
    var whole: [10]f32 = @splat(1.0);
    var whole_left: u32 = 7;
    _ = AudioMath.ApplyFade(1, &whole, &whole_left, 7);

    var split: [10]f32 = @splat(1.0);
    var split_left: u32 = 7;
    try std.testing.expectEqual(3, AudioMath.ApplyFade(1, split[0..3], &split_left, 7));
    try std.testing.expectEqual(4, split_left);
    try std.testing.expectEqual(4, AudioMath.ApplyFade(1, split[3..], &split_left, 7));

    try std.testing.expectEqualSlices(f32, &whole, &split);
    try std.testing.expectEqual(0, split_left);
}

test "a finished fade silences the whole buffer" {
    var samples = [_]f32{ 1.0, 1.0, 1.0, 1.0 };
    var frames_left: u32 = 0;

    try std.testing.expectEqual(0, AudioMath.ApplyFade(2, &samples, &frames_left, 240));
    try std.testing.expectEqualSlices(f32, &.{ 0.0, 0.0, 0.0, 0.0 }, &samples);
}

test "gain moves toward its target at a fixed speed and stops there" {
    var samples: [6]f32 = @splat(1.0);
    var gain: f32 = 1.0;

    AudioMath.ApplyGainTowards(1, &samples, &gain, 0.0, 0.25);
    try std.testing.expectEqualSlices(f32, &.{ 0.75, 0.5, 0.25, 0.0, 0.0, 0.0 }, &samples);
    try std.testing.expectEqual(0.0, gain);
}

test "full gain to silence takes exactly fade_frames whatever the step adds up to" {
    const fade_frames = 240;
    var samples: [fade_frames * 2]f32 = @splat(1.0);
    var gain: f32 = 1.0;

    AudioMath.ApplyGainTowards(2, &samples, &gain, 0.0, 1.0 / @as(f32, fade_frames));
    //the last frame of the fade is silent, the one before it is not
    try std.testing.expectEqual(0.0, samples[(fade_frames - 1) * 2]);
    try std.testing.expect(samples[(fade_frames - 2) * 2] > 0.0);
    try std.testing.expectEqual(0.0, gain);
}

test "gain split across calls matches one call" {
    var whole: [9]f32 = @splat(1.0);
    var whole_gain: f32 = 0.0;
    AudioMath.ApplyGainTowards(1, &whole, &whole_gain, 1.0, 0.125);

    var split: [9]f32 = @splat(1.0);
    var split_gain: f32 = 0.0;
    AudioMath.ApplyGainTowards(1, split[0..4], &split_gain, 1.0, 0.125);
    AudioMath.ApplyGainTowards(1, split[4..], &split_gain, 1.0, 0.125);

    try std.testing.expectEqualSlices(f32, &whole, &split);
    try std.testing.expectEqual(whole_gain, split_gain);
}

test "gain already at its target is a plain gain" {
    var samples = [_]f32{ 2.0, -4.0 };
    var gain: f32 = 0.5;
    AudioMath.ApplyGainTowards(1, &samples, &gain, 0.5, 0.01);
    try std.testing.expectEqualSlices(f32, &.{ 1.0, -2.0 }, &samples);
}
