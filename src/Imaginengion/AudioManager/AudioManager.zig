const std = @import("std");
const AudioContext = @import("AudioContext.zig");
const SPSCRingBuffer = @import("../Core/SPSCRingBuffer.zig");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const AssetHandle = @import("../ECSObjects/AssetHandle.zig");
const AudioAsset = @import("../ECSComponents/AComponents.zig").AudioAsset;
const AudioManager = @This();

pub const AUDIO_FORMAT = f32;
pub const AUDIO_CHANNELS = 2;
pub const SAMPLE_RATE = 48000;
pub const BUFFER_CAPACITY = 8192; //in samples, so 4096 stereo frames (~85ms). has to be a power of 2
pub const TAudioBuffer = SPSCRingBuffer.SPSCRingBuffer(f32, BUFFER_CAPACITY);

/// How many frames OnUpdate keeps queued ahead of the device (2400 = 50ms at 48kHz). Each update tops the
/// output buffer back up to this instead of producing dt's worth of audio, so the game clock and the sound
/// card's clock can never drift apart. It has to cover the longest gap between two updates (a 60fps frame
/// is 800 frames) or the device runs dry, and it is also the latency before a new sound is heard.
pub const TARGET_FRAMES = 2400;

comptime {
    if (TARGET_FRAMES * AUDIO_CHANNELS > BUFFER_CAPACITY) {
        @compileError("TARGET_FRAMES does not fit in the output buffer!");
    }
}

//TODO: remove once the voice pool can play sounds from AudioComponents (step 3 of the audio plan)
const DEBUG_SOUND_PATH = "src/Imaginengion/EngineAssets/sounds/DefaultSound.mp3";
const DEBUG_SOUND_VOLUME = 0.3;

pub const AudioStats = struct {
    mNum2DAudio: usize = 0,
    mNum3DAudio: usize = 0,
};

mAudioStats: AudioStats = .{},
mAudioContext: AudioContext = .{},

/// The mixed output the device thread reads from. It lives here rather than on any ECS component because
/// the device thread holds a raw pointer to it, and ECS storage moves when it grows. One per output device.
mOutputBuffer: TAudioBuffer = .default,

//a stand-in for one voice until the voice pool exists: a handle, not an *AudioAsset, since the asset can be
//reloaded between updates, and a cursor, since the asset itself holds no playback state
mDebugSound: AssetHandle = .uninit,
mDebugSoundCursor: u64 = 0,

pub fn Init(self: *AudioManager) !void {
    try self.mAudioContext.Init();
    self.mAudioContext.SetAudioBuffer(&self.mOutputBuffer);
}

pub fn Deinit(self: *AudioManager) void {
    self.mDebugSound.ReleaseAsset();
    self.mAudioContext.RemoveAudioBuffer();
    self.mAudioContext.Deinit();
}

pub fn OnUpdate(self: *AudioManager, engine_context: *EngineContext) !void {
    const buffered_frames = self.mOutputBuffer.AvailableRead() / AUDIO_CHANNELS;

    Tracy.Plot("Audio/Buffered Frames", .{ .color = 0x8BC34A }, buffered_frames);
    Tracy.Plot("Audio/Underruns", .{ .color = 0xF44336 }, self.mAudioContext.GetUnderrunCount());

    if (buffered_frames >= TARGET_FRAMES) return;

    const frame_allocator = engine_context.FrameAllocator();
    const frames_to_produce = TARGET_FRAMES - buffered_frames;
    const mixed_buffer = try frame_allocator.alloc(f32, frames_to_produce * AUDIO_CHANNELS);
    @memset(mixed_buffer, 0);

    //each voice reads into this first, then gets its volume applied as it is added to the mix
    const voice_buffer = try frame_allocator.alloc(f32, frames_to_produce * AUDIO_CHANNELS);

    try self.MixDebugSound(engine_context, mixed_buffer, voice_buffer);

    for (mixed_buffer) |*sample| {
        sample.* = std.math.clamp(sample.*, -1.0, 1.0);
    }

    _ = self.mOutputBuffer.PushSlice(mixed_buffer);
}

/// Loops DefaultSound.mp3 through the same path a voice will: fetch the asset by handle, read from the cursor,
/// scale by volume, add into the mix
fn MixDebugSound(self: *AudioManager, engine_context: *EngineContext, mixed_buffer: []f32, voice_buffer: []f32) !void {
    if (!self.mDebugSound.IsIDValid()) {
        self.mDebugSound = try engine_context.mAssetManager.GetAssetHandle(engine_context, .{ .File = .{ .rel_path = DEBUG_SOUND_PATH, .path_type = .Eng } });
    }

    const audio_asset = try self.mDebugSound.GetAsset(engine_context, AudioAsset);
    const frames_read = audio_asset.ReadFrames(voice_buffer, &self.mDebugSoundCursor, true);
    const samples_read = frames_read * AUDIO_CHANNELS;

    for (mixed_buffer[0..samples_read], voice_buffer[0..samples_read]) |*mixed, source| {
        mixed.* += source * DEBUG_SOUND_VOLUME;
    }
}
