const std = @import("std");

//the per-sample math the AudioManager's mix stages run. Buffers are interleaved, `channels` samples per frame

/// Pitch is clamped to this range. Below the minimum a voice would barely move, and at 0 it would never finish and
/// hold its voice slot forever. The maximum only guards against nonsense values, it is far above anything usable
pub const MIN_PITCH: f32 = 0.01;
pub const MAX_PITCH: f32 = 16.0;

/// Reads frames out of samples into frames_out, starting at cursor and moving it forward by pitch frames per output
/// frame. Pitch 1 plays the sound as it is, 2 twice as fast and an octave up, 0.5 half as fast and an octave down:
/// speed and pitch change together, like a record played at the wrong speed.
///
/// A cursor that lands between two frames gets a blend of both (linear interpolation): at 10.25 it is 75% of frame 10
/// and 25% of frame 11. Cheap, and fine within about 0.5-2. Far above that, skipped frames can fold high frequencies
/// back into audible harsh tones (aliasing), and every pitch other than 1 dulls the highs a little.
///
/// With loop set it wraps back to the start until frames_out is full, blending the last frame into the first so the
/// loop point is seamless. Without it, it stops at the end and returns fewer frames than asked for, 0 once done.
/// Returns how many frames were written. All the state between calls is the cursor, so reading in several calls gives
/// the same result as reading in one
pub fn Read(comptime channels: usize, samples: []const f32, frames_out: []f32, cursor: *f64, pitch: f32, loop: bool) u64 {
    std.debug.assert(samples.len % channels == 0);
    std.debug.assert(frames_out.len % channels == 0);

    const frame_count = samples.len / channels;
    if (frame_count == 0) return 0;
    const frame_count_f: f64 = @floatFromInt(frame_count);
    const step: f64 = std.math.clamp(pitch, MIN_PITCH, MAX_PITCH);

    if (cursor.* < 0.0) cursor.* = 0.0;

    const frames_requested = frames_out.len / channels;
    var frames_written: u64 = 0;
    while (frames_written < frames_requested) {
        //also covers a hot reload swapping a shorter sound in under a playing voice
        if (cursor.* >= frame_count_f) {
            if (!loop) break;
            //a mod rather than a subtract: a high pitch on a very short sound can step past the end more than once
            cursor.* = @mod(cursor.*, frame_count_f);
        }

        //the cursor is below frame_count, so this is always a valid frame
        const index: usize = @intFromFloat(cursor.*);
        const blend: f32 = @floatCast(cursor.* - @as(f64, @floatFromInt(index)));
        //past the last frame is the first again when looping, otherwise the last frame is held
        const next_index = if (index + 1 < frame_count) index + 1 else if (loop) 0 else index;

        const current_frame = samples[index * channels ..][0..channels];
        const next_frame = samples[next_index * channels ..][0..channels];
        const out_frame = frames_out[frames_written * channels ..][0..channels];
        for (out_frame, current_frame, next_frame) |*out, current, next| {
            out.* = current + (next - current) * blend;
        }

        cursor.* += step;
        frames_written += 1;
    }

    return frames_written;
}

/// Scales samples by a gain that slides evenly from `from` to `to` across the buffer, reaching `to` on the last frame.
/// A gain that jumps between two buffers is an audible step (a click, or "zipper" noise when it keeps changing), so a
/// changed volume is slid to over one buffer instead. `from` is the gain the previous buffer ended on
pub fn ApplyRamp(comptime channels: usize, samples: []f32, from: f32, to: f32) void {
    std.debug.assert(samples.len % channels == 0);
    const frame_count = samples.len / channels;
    if (frame_count == 0) return;

    if (from == to) {
        for (samples) |*sample| sample.* *= to;
        return;
    }

    const step = (to - from) / @as(f32, @floatFromInt(frame_count));
    for (0..frame_count) |frame| {
        const gain = from + step * @as(f32, @floatFromInt(frame + 1));
        for (samples[frame * channels ..][0..channels]) |*sample| sample.* *= gain;
    }
}

/// Fades samples toward silence, one step per frame, over fade_frames frames in total. frames_left is how much of the
/// fade is still to go, and counts down as frames are faded, so a fade longer than one buffer carries on in the next
/// call. Cutting a sound off mid-waveform is an audible click; 5ms of fade is too short to hear as a fade but long
/// enough to remove it. Frames after the fade ends are silenced. Returns how many frames are still audible
pub fn ApplyFade(comptime channels: usize, samples: []f32, frames_left: *u32, fade_frames: u32) u64 {
    std.debug.assert(samples.len % channels == 0);
    std.debug.assert(fade_frames > 0);
    std.debug.assert(frames_left.* <= fade_frames);

    const frame_count = samples.len / channels;
    const fade_frames_f: f32 = @floatFromInt(fade_frames);

    var frame: usize = 0;
    while (frame < frame_count and frames_left.* > 0) : (frame += 1) {
        const gain = @as(f32, @floatFromInt(frames_left.*)) / fade_frames_f;
        for (samples[frame * channels ..][0..channels]) |*sample| sample.* *= gain;
        frames_left.* -= 1;
    }

    const audible_frames = frame;
    @memset(samples[audible_frames * channels ..], 0.0);
    return audible_frames;
}
