const std = @import("std");
const AudioContext = @import("AudioContext.zig");
const ECSManager = @import("../ECS/ECSManager.zig");
const Vec3f32 = @import("../Math/LinAlg.zig").Vec3f32;
const SPSCRingBuffer = @import("../Core/SPSCRingBuffer.zig");
const SceneManager = @import("../Scene/SceneManager.zig");
const EntityComponents = @import("../GameObjects/Components.zig");
const MicComponent = EntityComponents.MicComponent;
const EntityTransformComponent = EntityComponents.TransformComponent;
const AudioComponent = EntityComponents.AudioComponent;
const AudioManager = @This();

pub const AUDIO_FORMAT = f32;
pub const AUDIO_CHANNELS = 2;
pub const SAMPLE_RATE = 48000;
pub const BUFFER_CAPACITY = 8192; //sample rate * latency_seconds, but has to be power of 2
pub const tAudioBuffer = SPSCRingBuffer.SPSCRingBuffer(f32, BUFFER_CAPACITY);

pub const AudioStats = struct {
    mNum2DAudio: usize = 0,
    mNum3DAudio: usize = 0,
};

mAudioStats: AudioStats = .{},
mAudioContext: AudioContext = .{},

mFrameAccumulator: f32 = 0.0,

pub fn Init(self: *AudioManager) !void {
    try self.mAudioContext.Init();
}

pub fn Deinit(self: *AudioManager) void {
    self.mAudioContext.Deinit();
}

pub fn SetAudioBuffer(self: *AudioManager, buffer: *tAudioBuffer) void {
    self.mAudioContext.SetAudioBuffer(buffer);
}

pub fn RemoveAudioBuffer(self: *AudioManager) void {
    self.mAudioContext.RemoveAudioBuffer();
}

pub fn OnUpdate(self: *AudioManager, delta_time: f32, scene_manager: *SceneManager, mic_component: *MicComponent, mic_transform: *EntityTransformComponent, frame_allocator: std.mem.Allocator) !void {
    _ = mic_transform; //used later for when dealing with spacialized sounds but for now simply doing 2d sounds

    self.mFrameAccumulator += delta_time * SAMPLE_RATE;

    const frames_num: usize = @as(usize, @intFromFloat(self.mFrameAccumulator));
    const frames_to_produce = @min(frames_num, mic_component.mAudioBuffer.RemainingSpace());
    const samples_to_produce = frames_to_produce * AUDIO_CHANNELS;

    self.mFrameAccumulator -= @floatFromInt(frames_to_produce);

    if (samples_to_produce == 0) return;

    const audio_entities = try scene_manager.GetEntityGroup(
        .{ .Component = AudioComponent },
        frame_allocator,
    );

    var mixed_buffer = try frame_allocator.alloc(f32, samples_to_produce);
    var source_buffer = try frame_allocator.alloc(f32, samples_to_produce);
    @memset(mixed_buffer, 0);

    for (audio_entities.items) |entity_id| {
        const entity = scene_manager.GetEntity(entity_id);
        const audio_component = entity.GetComponent(AudioComponent).?;

        if (audio_component.mPlaybackState != .Playing) continue;

        const frames_read = try audio_component.ReadFrames(source_buffer[0..samples_to_produce], frames_to_produce);
        const samples_read = frames_read * AUDIO_CHANNELS;

        for (0..samples_read) |i| {
            var source = source_buffer[i];
            SourceVolume(audio_component, &source);
            mixed_buffer[i] += source;

            ClampMix(&mixed_buffer[i]);
        }
    }
    _ = mic_component.mAudioBuffer.PushSlice(mixed_buffer);
}

fn ClampMix(source: *f32) void {
    source.* = std.math.clamp(source.*, -1.0, 1.0);
}

fn SourceVolume(audio_component: *AudioComponent, source: *f32) void {
    source.* = source.* * audio_component.mVolume;
}
