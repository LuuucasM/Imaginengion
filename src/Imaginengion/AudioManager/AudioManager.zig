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
    //from the scene get all the objects with AudioComponent
    //frames to produce is dt * sample rate
    //process each sound according to its own parameters
    //volume, pitch, (later more stuff)
    //mix together all the different audio sources for the n number of frames
    //write n frames to ring bufferbuffer
}
