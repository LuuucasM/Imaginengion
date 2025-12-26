const std = @import("std");
const AudioContext = @import("AudioContext.zig");
const AudioFrameBuffer = @import("AudioFrameBuffer.zig").AudioFrameBuffer;
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

pub const AudioStats = struct {
    mNum2DAudio: usize = 0,
    mNum3DAudio: usize = 0,
};

var AudioGPA = std.heap.DebugAllocator(.{}).init;
const AudioAllocator = AudioGPA.allocator();

var ManagerInstance: AudioManager = .{};

mAudioStats: AudioStats = .{},
mAudioContext: AudioContext = .{},

pub fn Init() !void {
    try ManagerInstance.mAudioContext.Init(&ManagerInstance.mFrameBuffers);
}

pub fn Deinit() void {
    ManagerInstance.mAudioContext.Deinit();
}

pub fn OnUpdate(delta_time: f32, scene_manager: *SceneManager, mic_component: *MicComponent, mic_transform: *EntityTransformComponent, frame_allocator: std.mem.Allocator) void {
    _ = mic_transform; //used later for when dealing with spacialized sounds but for now simply doing 2d sounds

    const frames_num: usize = @as(usize, @intFromFloat(delta_time * @as(f32, @floatFromInt(SAMPLE_RATE))));
    const frames_to_produce = @min(frames_num, BUFFER_CAPACITY);
    const samples_to_produce = frames_to_produce * AUDIO_CHANNELS;

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
            //apply volume
            //apply pitch
            //add to mixed_buffer
        }
    }

    _ = mic_component.mAudioBuffer.PushSlice(mixed_buffer);
}
