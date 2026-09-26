const std = @import("std");
const AudioContext = @import("AudioContext.zig");
const SPSCRingBuffer = @import("../Core/SPSCRingBuffer.zig");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");

const ECSManager = @import("../ECS/ECSManager.zig");
const EventManager = @import("../Events/EventManager.zig");
const EventResult = EventManager.EventResult;
pub const EventData = @import("../Events/AudioManagerData.zig");
const ECSCore = @import("../ECSManagers/Manager.zig").Core;

const Voice = @import("../ECSObjects/Voice.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const VComponents = @import("../ECSComponents/VComponents.zig");
const VoiceComponent = VComponents.VoiceComponent;
const VoiceAssetComponent = VComponents.VoiceAssetComponent;
const VoiceVolumeComponent = VComponents.VoiceVolumeComponent;
const AudioComponent = @import("../ECSComponents/EComponents.zig").AudioComponent;
const AudioAsset = @import("../ECSComponents/AComponents.zig").AudioAsset;
const AudioManager = @This();

pub const ECSManagerT = ECSManager.ECSManager(Voice.Type, &VComponents.ComponentsList, "VoiceECS");
pub const EventManagerT = EventManager.EventManager(EventData);

const Core = ECSCore(AudioManager);

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

/// The most voices that can exist at once, across every world. PlayVoice refuses new ones past this rather than
/// cutting off one that is already playing
pub const MAX_VOICES = 64;

const VoiceState = union(enum) {
    /// Will never play again, and is waiting for its destroy
    Dead,
    /// Plays on regardless of its source, from its own copies
    Detached,
    /// Plays from this AudioComponent, its source's
    Attached: *AudioComponent,
};

comptime {
    if (TARGET_FRAMES * AUDIO_CHANNELS > BUFFER_CAPACITY) {
        @compileError("TARGET_FRAMES does not fit in the output buffer!");
    }
}

pub const AudioStats = struct {
    mNum2DAudio: usize = 0,
    mNum3DAudio: usize = 0,
};

mAudioStats: AudioStats = .{},
mAudioContext: AudioContext = .{},

/// The mixed output the device thread reads from. It lives here rather than on any ECS component because
/// the device thread holds a raw pointer to it, and ECS storage moves when it grows. One per output device.
mOutputBuffer: TAudioBuffer = .default,

mECSManager: ECSManagerT = .empty,
mEventManager: EventManagerT = .empty,

/// Hands out AudioComponent.mVoiceToken values, see NewVoiceToken
mNextVoiceToken: u32 = 0,

pub fn Init(self: *AudioManager, engine_allocator: std.mem.Allocator) !void {
    try self.mECSManager.Init(engine_allocator);
    try self.mAudioContext.Init();
    self.mAudioContext.SetAudioBuffer(&self.mOutputBuffer);
}

pub fn Deinit(self: *AudioManager, engine_context: *EngineContext) void {
    self.mAudioContext.RemoveAudioBuffer();
    self.mAudioContext.Deinit();
    self.mECSManager.Deinit(engine_context);
    self.mEventManager.Deinit(engine_context.EngineAllocator());
}

pub const SetSyncCallback = Core.SetSyncCallback;
pub const GetComponent = Core.GetComponent;
pub const HasComponent = Core.HasComponent;
pub const IsActiveObj = Core.IsActiveObj;
pub const GetGroup = Core.GetGroup;
const DeleteVoice = Core.DeleteObj;

/// Starts playing source's AudioComponent from the beginning, as an attached or detached voice depending on the
/// component's mStopWithSource. A component with no asset plays the asset manager's default sound, like any other
/// missing asset. Returns null, and logs why, when nothing can be played: the source has no AudioComponent, it is
/// detached and looping, or MAX_VOICES are already playing
pub fn PlayVoice(self: *AudioManager, engine_context: *EngineContext, source: Entity) !?Voice {
    if (!source.IsActive()) {
        std.log.warn("PlayVoice called with an entity that no longer exists", .{});
        return null;
    }
    const audio_component = source.GetComponent(AudioComponent) orelse {
        std.log.warn("PlayVoice called on an entity with no AudioComponent", .{});
        return null;
    };
    const is_attached = audio_component.mStopWithSource;
    if (!is_attached and audio_component.mLoop) {
        std.log.warn("PlayVoice refused: a looping sound has to stop with its source, or nothing could stop it", .{});
        return null;
    }
    if (self.mECSManager.NumWithComponent(VoiceComponent) >= MAX_VOICES) {
        std.log.warn("PlayVoice refused: all {d} voices are in use", .{MAX_VOICES});
        return null;
    }

    if (is_attached and audio_component.mVoiceToken == 0) {
        audio_component.mVoiceToken = self.NewVoiceToken();
    }

    //the voice lives in this manager's storage, so adding to it leaves audio_component (in the world's) where it is
    const engine_allocator = engine_context.EngineAllocator();
    const voice: Voice = .{ .mID = try self.mECSManager.CreateEntity(engine_allocator), .mManager = self };
    errdefer self.DeleteVoice(engine_context, voice.mID) catch {};

    _ = try self.mECSManager.AddComponent(engine_allocator, voice.mID, VoiceComponent{
        .mSource = if (is_attached) source else .uninit,
        .mToken = if (is_attached) audio_component.mVoiceToken else 0,
    });

    if (!is_attached) {
        //its own copy of everything it plays, since the source may be gone before it finishes
        audio_component.mAudioAsset.RetainAsset();
        _ = self.mECSManager.AddComponent(engine_allocator, voice.mID, VoiceAssetComponent{ .mAsset = audio_component.mAudioAsset }) catch |err| {
            var unused_handle = audio_component.mAudioAsset;
            unused_handle.ReleaseAsset();
            return err;
        };
        _ = try self.mECSManager.AddComponent(engine_allocator, voice.mID, VoiceVolumeComponent{ .mVolume = audio_component.mVolume });
    }

    return voice;
}

/// Silences the voice from the next mix on and queues its destroy for the end of the frame. Stopping a voice that has
/// already finished or been stopped does nothing
pub fn StopVoice(self: *AudioManager, engine_context: *EngineContext, voice: Voice) !void {
    if (!voice.IsActive()) return;
    self.GetComponent(VoiceComponent, voice.mID).?.mStopped = true;
    try self.DeleteVoice(engine_context, voice.mID);
}

/// A token no component holds yet. Never 0, which is what a component that has not played anything holds
fn NewVoiceToken(self: *AudioManager) u32 {
    self.mNextVoiceToken +%= 1;
    if (self.mNextVoiceToken == 0) self.mNextVoiceToken = 1;
    return self.mNextVoiceToken;
}

/// Mixes every voice into the output buffer, topping it back up to TARGET_FRAMES.
///
/// The mix runs in stages, each one a batch over every voice: read each voice's asset into its own buffer, apply
/// each voice's volume, then sum them all. New kinds of processing (pitch in the read, reverb, spatial) slot in as
/// stages of their own. Each stage reads its modifier from the voice's own component when it has one (a detached
/// voice's copies), and from its source's AudioComponent otherwise
pub fn OnUpdate(self: *AudioManager, engine_context: *EngineContext) !void {
    const buffered_frames = self.mOutputBuffer.AvailableRead() / AUDIO_CHANNELS;

    Tracy.Plot("Audio/Buffered Frames", .{ .color = 0x8BC34A }, buffered_frames);
    Tracy.Plot("Audio/Underruns", .{ .color = 0xF44336 }, self.mAudioContext.GetUnderrunCount());
    Tracy.Plot("Audio/Voices", .{ .color = 0x03A9F4 }, self.mECSManager.NumWithComponent(VoiceComponent));

    if (buffered_frames >= TARGET_FRAMES) return;

    const frame_allocator = engine_context.FrameAllocator();
    const frames_to_produce = TARGET_FRAMES - buffered_frames;
    const samples_to_produce = frames_to_produce * AUDIO_CHANNELS;

    const voices = try self.GetGroup(frame_allocator, .{ .Component = VoiceComponent });

    //one buffer per voice, back to back, since every stage needs every voice's output from the one before it
    const voice_buffers = try frame_allocator.alloc(f32, voices.items.len * samples_to_produce);
    const voice_frames = try frame_allocator.alloc(u64, voices.items.len);

    //read stage
    for (voices.items, 0..) |voice_id, i| {
        const voice_buffer = voice_buffers[i * samples_to_produce ..][0..samples_to_produce];
        voice_frames[i] = try self.ReadVoice(engine_context, voice_id, voice_buffer);
    }

    //volume stage
    for (voices.items, 0..) |voice_id, i| {
        if (voice_frames[i] == 0) continue;
        const volume = if (self.GetComponent(VoiceVolumeComponent, voice_id)) |own_volume|
            own_volume.mVolume
        else switch (self.GetVoiceState(voice_id)) {
            .Attached => |source_component| source_component.mVolume,
            else => continue,
        };
        const voice_samples = voice_buffers[i * samples_to_produce ..][0 .. voice_frames[i] * AUDIO_CHANNELS];
        for (voice_samples) |*sample| {
            sample.* *= volume;
        }
    }

    //mix stage
    const mixed_buffer = try frame_allocator.alloc(f32, samples_to_produce);
    @memset(mixed_buffer, 0);
    for (0..voices.items.len) |i| {
        const voice_samples = voice_buffers[i * samples_to_produce ..][0 .. voice_frames[i] * AUDIO_CHANNELS];
        for (mixed_buffer[0..voice_samples.len], voice_samples) |*mixed, sample| {
            mixed.* += sample;
        }
    }

    for (mixed_buffer) |*sample| {
        sample.* = std.math.clamp(sample.*, -1.0, 1.0);
    }

    _ = self.mOutputBuffer.PushSlice(mixed_buffer);
}

/// Reads the next frames of one voice into voice_buffer and returns how many were read. Queues the voice's destroy
/// once it has nothing more to play: it is dead (see GetVoiceState), or it reached the end without looping
fn ReadVoice(self: *AudioManager, engine_context: *EngineContext, voice_id: Voice.Type, voice_buffer: []f32) !u64 {
    const voice_state = self.GetVoiceState(voice_id);
    if (voice_state == .Dead) {
        try self.DeleteVoice(engine_context, voice_id);
        return 0;
    }

    const voice_component = self.GetComponent(VoiceComponent, voice_id).?;

    const asset_handle, const loop = if (self.GetComponent(VoiceAssetComponent, voice_id)) |own_asset|
        .{ own_asset.mAsset, false }
    else switch (voice_state) {
        .Attached => |source_component| .{ source_component.mAudioAsset, source_component.mLoop },
        //a detached voice always has its own asset
        .Detached, .Dead => unreachable,
    };
    //fetched every update rather than kept, since a hot reload can swap the asset out between updates.
    //loading an asset only touches the asset manager's storage, so the component pointers above stay valid.
    //asked of the asset manager by id rather than through the handle: an unset handle has no manager pointer, and
    //the asset manager answers an unset id with its default sound
    const audio_asset = try engine_context.mAssetManager.GetAsset(engine_context, AudioAsset, asset_handle.mID);
    const frames_read = audio_asset.ReadFrames(voice_buffer, &voice_component.mCursor, loop);

    if (frames_read < voice_buffer.len / AUDIO_CHANNELS) {
        try self.DeleteVoice(engine_context, voice_id);
    }
    return frames_read;
}

/// Whether a voice can still play, and for an attached voice the AudioComponent it plays from. A voice is dead once it
/// is stopped, and an attached one also once its source entity or AudioComponent is gone or the component's token
/// has moved on (StopVoices, or a copy of the component: a cleared and re-copied world keeps its entity ids, but
/// every copied component starts at token 0)
fn GetVoiceState(self: *AudioManager, voice_id: Voice.Type) VoiceState {
    const voice_component = self.GetComponent(VoiceComponent, voice_id).?;
    if (voice_component.mStopped) return .Dead;

    const source = voice_component.mSource;
    if (!source.IsIDValid()) return .Detached;
    if (!source.IsActive()) return .Dead;
    const source_component = source.GetComponent(AudioComponent) orelse return .Dead;
    if (source_component.mVoiceToken != voice_component.mToken) return .Dead;
    return .{ .Attached = source_component };
}

/// Runs the voice destroys queued this frame: the manager events hand each one to the ECS as a destroy, then the
/// ECS events actually free it
pub fn ProcessDestroyedVoices(self: *AudioManager, engine_context: *EngineContext) !void {
    var callback_list: std.DoublyLinkedList = .{};
    try self.ProcessEvents(EventData, .EndOfFrame, engine_context, &callback_list);
    try self.mECSManager.ProcessEvents(engine_context, .EndOfFrame, &callback_list);
}

pub fn ProcessEvents(self: *AudioManager, comptime event_data: type, comptime event_category: event_data.EventCategories, engine_context: *EngineContext, callback_list: *std.DoublyLinkedList) !void {
    if (event_data == EventData) {
        var callback = EventManagerT.EventCallback{
            .mCtx = self,
            .mCallbackFn = struct {
                fn thunk(ctx: *anyopaque, ec: *EngineContext, event: *const event_data.EventT) anyerror!EventResult {
                    return @as(*AudioManager, @ptrCast(@alignCast(ctx))).OnManagerEvents(ec, event.*);
                }
            }.thunk,
        };
        //the node is ours, but the list belongs to the caller, so unlink again on the way out
        callback_list.append(&callback.mNode);
        defer callback_list.remove(&callback.mNode);

        try self.mEventManager.ProcessCategory(event_category, engine_context, callback_list.*);
        self.mEventManager.ClearCategory(engine_context.EngineAllocator(), event_category, .ClearRetainingCapacity);
    } else {
        std.log.err("AudioManager.ProcessEvents does not currently handle processing events of type {s}", .{@typeName(event_data)});
    }
}

pub fn OnManagerEvents(self: *AudioManager, engine_context: *EngineContext, event: EventData.EventT) anyerror!EventResult {
    switch (event) {
        .DestroyVoice => |e| {
            if (self.mECSManager.IsActiveEntity(e.Voice.mID)) {
                try self.mECSManager.DestroyEntity(engine_context, e.Voice.mID);
            }
        },
        .Default => unreachable,
    }
    return .Continue;
}
