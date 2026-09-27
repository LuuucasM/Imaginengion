const std = @import("std");
const AudioContext = @import("AudioContext.zig");
const AudioMath = @import("../Math/Audio.zig");
const SPSCRingBuffer = @import("../Core/SPSCRingBuffer.zig");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");

const ECSManager = @import("../ECS/ECSManager.zig");
const EventManager = @import("../Events/EventManager.zig");
const EventResult = EventManager.EventResult;
pub const EventData = @import("../Events/AudioManagerData.zig");
const ECSCore = @import("../ECSManagers/Manager.zig").Core;

const Voice = @import("../ECSObjects/Voice.zig");
const Bus = @import("../ECSObjects/Bus.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const VComponents = @import("../ECSComponents/VComponents.zig");
const VoiceComponent = VComponents.VoiceComponent;
const VoiceAssetComponent = VComponents.VoiceAssetComponent;
const VoicePitchComponent = VComponents.VoicePitchComponent;
const VoiceFadeComponent = VComponents.VoiceFadeComponent;
const BusComponent = VComponents.BusComponent;
const VolumeComponent = VComponents.VolumeComponent;
const NameComponent = VComponents.NameComponent;
const UUIDComponent = VComponents.UUIDComponent;
const TextSerializer = @import("../Serializer/TextSerializer.zig");
const ParentComponent = @import("../ECS/Components.zig").ParentComponent(Bus.Type);
const ChildComponent = @import("../ECS/Components.zig").ChildComponent(Bus.Type);
const AudioComponent = @import("../ECSComponents/EComponents.zig").AudioComponent;
const AudioAsset = @import("../ECSComponents/AComponents.zig").AudioAsset;
const AudioManager = @This();

//voices and buses share this one ECS, told apart by their components (VoiceComponent, BusComponent)
pub const ECSManagerT = ECSManager.ECSManager(Voice.Type, &VComponents.ComponentsList, "AudioECS");
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

/// How long a stopping voice fades out for (240 = 5ms at 48kHz). Cutting a sound off mid-waveform clicks; this is too
/// short to hear as a fade but long enough to remove the click
pub const FADE_FRAMES: u32 = 240;

const VoiceState = union(enum) {
    /// Plays on regardless of its source, from its own copies
    Detached,
    /// Plays from this AudioComponent, its source's
    Attached: *AudioComponent,
    /// Was attached, but its source entity or AudioComponent is gone, or the component's token has moved on. Fades
    /// out what it played last (VoiceComponent's mAssetID, mLastVolume, mLastPitch)
    Orphaned,
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
/// Bus UUID -> the bus, for turning a saved bus reference back into a bus
mUUIDToWorldID: std.AutoHashMapUnmanaged(u64, Bus.Type) = .empty,

/// Hands out AudioComponent.mVoiceToken values, see NewVoiceToken
mNextVoiceToken: u32 = 0,

/// The root of the bus tree, made in Init. Everything is mixed through it, and it can not be deleted
mMasterBus: Bus = .uninit,

pub fn Init(self: *AudioManager, engine_context: *EngineContext) !void {
    try self.InitMixer(engine_context);
    try self.mAudioContext.Init();
    self.mAudioContext.SetAudioBuffer(&self.mOutputBuffer);
}

pub fn Deinit(self: *AudioManager, engine_context: *EngineContext) void {
    self.mAudioContext.RemoveAudioBuffer();
    self.mAudioContext.Deinit();
    self.DeinitMixer(engine_context);
}

/// Voices and buses without the output device. Init is this and then the device; tests use it on its own, to work
/// with voices and buses without a sound card. Pair it with DeinitMixer
pub fn InitMixer(self: *AudioManager, engine_context: *EngineContext) !void {
    try self.mECSManager.Init(engine_context.EngineAllocator());
    self.mMasterBus = try self.NewBus(engine_context, null, Bus.DefaultConfig, "Master");
}

pub fn DeinitMixer(self: *AudioManager, engine_context: *EngineContext) void {
    self.mECSManager.Deinit(engine_context);
    self.mEventManager.Deinit(engine_context.EngineAllocator());
    self.mUUIDToWorldID.deinit(engine_context.EngineAllocator());
}

pub const SetSyncCallback = Core.SetSyncCallback;
pub const GetComponent = Core.GetComponent;
pub const HasComponent = Core.HasComponent;
pub const IsActiveObj = Core.IsActiveObj;
pub const GetGroup = Core.GetGroup;
pub const AddComponent = Core.AddComponent;
pub const AddUUID = Core.AddUUID;
pub const RemoveUUID = Core.RemoveUUID;
pub const GetWorldID = Core.GetWorldID;

/// The manager an object of type obj_t is kept in, as the world's GetManager does it. Voices and buses are both kept
/// here. Lets code written for any object type (e.g. UUIDComponent.PostParse) reach this one the same way
pub fn GetManager(self: *AudioManager, comptime obj_t: type) *AudioManager {
    comptime std.debug.assert(obj_t == Voice or obj_t == Bus);
    return self;
}
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
        //so a voice orphaned before its first mix still knows what to fade out, and does not slide in from silence
        .mAssetID = audio_component.mAudioAsset.mID,
        .mLastVolume = audio_component.mVolume,
        .mLastPitch = audio_component.mPitch,
        .mBusID = audio_component.mBus.mID,
    });

    if (!is_attached) {
        //its own copy of everything it plays, since the source may be gone before it finishes
        audio_component.mAudioAsset.RetainAsset();
        _ = self.mECSManager.AddComponent(engine_allocator, voice.mID, VoiceAssetComponent{ .mAsset = audio_component.mAudioAsset }) catch |err| {
            var unused_handle = audio_component.mAudioAsset;
            unused_handle.ReleaseAsset();
            return err;
        };
        _ = try self.mECSManager.AddComponent(engine_allocator, voice.mID, VolumeComponent{ .mVolume = audio_component.mVolume });
        _ = try self.mECSManager.AddComponent(engine_allocator, voice.mID, VoicePitchComponent{ .mPitch = audio_component.mPitch });
    }

    return voice;
}

/// Fades the voice out over FADE_FRAMES from the next mix on, after which it is destroyed. Stopping a voice that has
/// already finished or is already stopping does nothing
pub fn StopVoice(self: *AudioManager, engine_context: *EngineContext, voice: Voice) !void {
    if (!voice.IsActive()) return;
    try self.StartFade(engine_context, voice.mID);
}

fn StartFade(self: *AudioManager, engine_context: *EngineContext, voice_id: Voice.Type) !void {
    if (self.HasComponent(VoiceFadeComponent, voice_id)) return;
    _ = try self.mECSManager.AddComponent(engine_context.EngineAllocator(), voice_id, VoiceFadeComponent{ .mFramesLeft = FADE_FRAMES });
}

/// A token no component holds yet. Never 0, which is what a component that has not played anything holds
fn NewVoiceToken(self: *AudioManager) u32 {
    self.mNextVoiceToken +%= 1;
    if (self.mNextVoiceToken == 0) self.mNextVoiceToken = 1;
    return self.mNextVoiceToken;
}

/// The root bus. Everything is mixed through it, and it can not be deleted
pub fn GetMasterBus(self: *AudioManager) Bus {
    return self.mMasterBus;
}

/// A new bus under parent (under Master if parent is not a bus), unpaused, with config's components
pub fn CreateBus(self: *AudioManager, engine_context: *EngineContext, parent: Bus, config: Bus.CreateConfig) !Bus {
    return try self.NewBus(engine_context, self.ResolveBus(parent.mID), config, "Bus");
}

/// The bus with this UUID, or null if no bus has it
pub fn GetBusByUUID(self: *AudioManager, uuid: u64) ?Bus {
    const bus_id = self.GetWorldID(uuid) orelse return null;
    if (!self.IsBus(bus_id)) return null;
    return .{ .mID = bus_id, .mManager = self };
}

/// Deletes the bus and every bus under it at the end of the frame, through the ECS, which destroys children with
/// their parent. Voices playing into them fall back to Master. Deleting Master, or a bus that is already gone or
/// already queued, does nothing
pub fn DeleteBus(self: *AudioManager, engine_context: *EngineContext, bus: Bus) !void {
    if (bus.mID == self.mMasterBus.mID) {
        std.log.warn("The Master bus can not be deleted", .{});
        return;
    }
    try self.QueueBusDestroy(engine_context, bus);
}

fn QueueBusDestroy(self: *AudioManager, engine_context: *EngineContext, bus: Bus) !void {
    if (!self.IsBus(bus.mID)) return;

    const event: EventData.EventT = .{ .DestroyBus = .{ .Bus = .{ .mID = bus.mID, .mManager = self } } };
    for (self.mEventManager.mEventsArray.getPtr(.EndOfFrame).items) |queued_event| {
        if (std.meta.eql(queued_event, event)) return;
    }
    try self.mEventManager.Insert(engine_context.EngineAllocator(), .EndOfFrame, event);
}

/// bus_id if it is a live bus, otherwise Master: what an unset (uninit) or since deleted bus plays into
pub fn ResolveBus(self: *AudioManager, bus_id: Bus.Type) Bus.Type {
    return if (self.IsBus(bus_id)) bus_id else self.mMasterBus.mID;
}

fn IsBus(self: *AudioManager, id: Bus.Type) bool {
    return self.mECSManager.IsActiveEntity(id) and self.HasComponent(BusComponent, id);
}

fn NewBus(self: *AudioManager, engine_context: *EngineContext, parent_id: ?Bus.Type, config: Bus.CreateConfig, name: []const u8) !Bus {
    const engine_allocator = engine_context.EngineAllocator();

    const bus_id = if (parent_id) |parent|
        try self.mECSManager.AddChild(engine_allocator, parent, .Entity)
    else
        try self.mECSManager.CreateEntity(engine_allocator);

    //what makes it a bus, so not up to the config: a blank bus being read from a file still needs one
    _ = try self.mECSManager.AddComponent(engine_allocator, bus_id, BusComponent{});

    if (config.bAddVolume) {
        _ = try self.mECSManager.AddComponent(engine_allocator, bus_id, VolumeComponent{});
    }
    if (config.bAddName) {
        var name_component: NameComponent = .empty;
        try name_component.mName.appendSlice(engine_allocator, name);
        _ = self.mECSManager.AddComponent(engine_allocator, bus_id, name_component) catch |err| {
            name_component.mName.deinit(engine_allocator);
            return err;
        };
    }
    if (config.bAddUUID) {
        const io_source = std.Random.IoSource{ .io = engine_context.Io() };
        const uuid = io_source.interface().int(u64);
        _ = try self.mECSManager.AddComponent(engine_allocator, bus_id, UUIDComponent{ .ID = uuid });
        try self.AddUUID(engine_allocator, uuid, bus_id);
    }

    return .{ .mID = bus_id, .mManager = self };
}

//=========================================== PROJECT SETTINGS ===========================================
//the bus tree is kept per project, in ProjectSettings/Audio.json (see Project.zig). Voices are not: what is playing
//is not part of a project

pub const ProjectSettingsName = "Audio";

pub fn SaveProjectSettings(self: *AudioManager, engine_context: *EngineContext, write_stream: *std.json.Stringify) !void {
    try write_stream.beginObject();
    try write_stream.objectField("Buses");
    try TextSerializer.WriteObject(write_stream, engine_context.FrameAllocator(), self.mMasterBus);
    try write_stream.endObject();
}

/// Replaces the bus tree with the one in the settings. Settings without one leave a new project's tree
pub fn LoadProjectSettings(self: *AudioManager, engine_context: *EngineContext, scanner: *std.json.Scanner) !void {
    try self.ResetProjectSettings(engine_context);

    if (.object_begin != try scanner.next()) return error.UnexpectedToken;
    while (true) {
        const key = switch (try scanner.nextAlloc(engine_context.FrameAllocator(), .alloc_if_needed)) {
            .object_end => break,
            inline .string, .allocated_string => |slice| slice,
            else => return error.UnexpectedToken,
        };

        if (std.mem.eql(u8, key, "Buses")) {
            //read into a blank bus rather than the Master that is there, which already has the components the file
            //has, and the ECS adds a component to an object only once
            const new_master = try self.NewBus(engine_context, null, Bus.BlankConfig, "Master");
            try TextSerializer.ReadObject(engine_context, scanner, new_master);
            try self.ReplaceMasterBus(engine_context, new_master);
        } else {
            std.log.warn("Skipping unknown key '{s}' in the audio settings", .{key});
            try scanner.skipValue();
        }
    }
}

/// Back to a new project's bus tree: a Master at full volume with nothing under it
pub fn ResetProjectSettings(self: *AudioManager, engine_context: *EngineContext) !void {
    try self.ReplaceMasterBus(engine_context, try self.NewBus(engine_context, null, Bus.DefaultConfig, "Master"));
}

/// Makes new_master the root and queues the old tree's destroy for the end of the frame. Until then the old buses are
/// still there but not mixed, so anything playing into them is silent for what is left of the frame; after that it
/// falls back to the new Master, like any voice whose bus was deleted
fn ReplaceMasterBus(self: *AudioManager, engine_context: *EngineContext, new_master: Bus) !void {
    const old_master = self.mMasterBus;
    self.mMasterBus = new_master;
    try self.QueueBusDestroy(engine_context, old_master);
}
//========================================= END PROJECT SETTINGS =========================================

/// Whether voices playing into this bus are held where they are: it, or a bus above it, is paused and has faded all
/// the way out. Until the fade is done they keep playing, so the fade has something to fade
fn IsBusHeld(self: *AudioManager, bus_id: Bus.Type) bool {
    var current_id = bus_id;
    while (true) {
        const bus_component = self.GetComponent(BusComponent, current_id).?;
        if (bus_component.mPaused and bus_component.mGain == 0.0) return true;
        //Master is the only bus without a parent
        const child_component = self.GetComponent(ChildComponent, current_id) orelse return false;
        current_id = child_component.mParent;
    }
}

/// Mixes every voice into the output buffer, topping it back up to TARGET_FRAMES.
///
/// The mix runs in stages, each one a batch over every voice: read each voice's asset into its own buffer at its
/// pitch, apply each voice's volume, fade out the ones that are stopping, then mix them through the bus tree. Pitch is
/// part of the read
/// rather than a stage after it, since it decides how much of the asset is read. New kinds of processing (reverb,
/// spatial) slot in as stages of their own. Where a stage gets its modifier depends on the voice (see VoiceState):
/// live from its source's AudioComponent, from its own copies, or from what it played last
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

    //volume stage: a changed volume slides over from the last one across this buffer instead of jumping
    for (voices.items, 0..) |voice_id, i| {
        if (voice_frames[i] == 0) continue;
        const voice_component = self.GetComponent(VoiceComponent, voice_id).?;
        const volume = switch (self.GetVoiceState(voice_id)) {
            .Attached => |source_component| source_component.mVolume,
            .Detached => self.GetComponent(VolumeComponent, voice_id).?.mVolume,
            .Orphaned => voice_component.mLastVolume,
        };
        const voice_samples = voice_buffers[i * samples_to_produce ..][0 .. voice_frames[i] * AUDIO_CHANNELS];
        AudioMath.ApplyRamp(AUDIO_CHANNELS, voice_samples, voice_component.mLastVolume, volume);
        voice_component.mLastVolume = volume;
    }

    //fade stage
    for (voices.items, 0..) |voice_id, i| {
        const fade_component = self.GetComponent(VoiceFadeComponent, voice_id) orelse continue;
        const voice_samples = voice_buffers[i * samples_to_produce ..][0 .. voice_frames[i] * AUDIO_CHANNELS];
        //anything after the end of the fade is silent, so it is left out of the mix
        voice_frames[i] = AudioMath.ApplyFade(AUDIO_CHANNELS, voice_samples, &fade_component.mFramesLeft, FADE_FRAMES);
        if (fade_component.mFramesLeft == 0) {
            try self.DeleteVoice(engine_context, voice_id);
        }
    }

    //bus stage: each voice is added into its bus, then the tree is mixed children first, each bus applying its own
    //gain before it is added into its parent. What comes out of Master is the mix
    const buses = try self.GetGroup(frame_allocator, .{ .Component = BusComponent });
    const bus_buffers = try frame_allocator.alloc(f32, buses.items.len * samples_to_produce);
    @memset(bus_buffers, 0);

    var bus_indices: BusIndices = .empty;
    try bus_indices.ensureTotalCapacity(frame_allocator, @intCast(buses.items.len));
    for (buses.items, 0..) |bus_id, i| {
        bus_indices.putAssumeCapacity(bus_id, i);
    }

    for (voices.items, 0..) |voice_id, i| {
        const voice_samples = voice_buffers[i * samples_to_produce ..][0 .. voice_frames[i] * AUDIO_CHANNELS];
        if (voice_samples.len == 0) continue;
        const bus_id = self.ResolveBus(self.GetComponent(VoiceComponent, voice_id).?.mBusID);
        const bus_buffer = bus_buffers[bus_indices.get(bus_id).? * samples_to_produce ..][0..samples_to_produce];
        for (bus_buffer[0..voice_samples.len], voice_samples) |*mixed, sample| {
            mixed.* += sample;
        }
    }

    const mixed_buffer = self.MixBus(self.mMasterBus.mID, bus_buffers, samples_to_produce, &bus_indices);

    for (mixed_buffer) |*sample| {
        sample.* = std.math.clamp(sample.*, -1.0, 1.0);
    }

    _ = self.mOutputBuffer.PushSlice(mixed_buffer);
}

const BusIndices = std.AutoHashMapUnmanaged(Bus.Type, usize);

/// Adds every bus under bus_id into its buffer, each one mixed the same way first, then applies this bus's gain.
/// The gain moves toward the bus's volume, or 0 while it is paused, at a fixed speed: full to silent in FADE_FRAMES,
/// so a pause always fades over the same few ms and a volume change glides. Returns the bus's buffer
fn MixBus(self: *AudioManager, bus_id: Bus.Type, bus_buffers: []f32, samples_per_bus: usize, bus_indices: *const BusIndices) []f32 {
    const bus_buffer = bus_buffers[bus_indices.get(bus_id).? * samples_per_bus ..][0..samples_per_bus];

    //only buses are ever children in this ECS, voices never are
    const first_child = if (self.GetComponent(ParentComponent, bus_id)) |parent_component| parent_component.mFirstEntity else Bus.NullObject;
    if (first_child != Bus.NullObject) {
        var child_id = first_child;
        while (true) {
            const next_id = self.GetComponent(ChildComponent, child_id).?.mNext;
            const child_buffer = self.MixBus(child_id, bus_buffers, samples_per_bus, bus_indices);
            for (bus_buffer, child_buffer) |*mixed, sample| {
                mixed.* += sample;
            }
            if (next_id == first_child) break; //the list is circular
            child_id = next_id;
        }
    }

    const bus_component = self.GetComponent(BusComponent, bus_id).?;
    const volume = if (self.GetComponent(VolumeComponent, bus_id)) |volume_component| volume_component.mVolume else 1.0;
    const target_gain = if (bus_component.mPaused) 0.0 else volume;
    AudioMath.ApplyGainTowards(AUDIO_CHANNELS, bus_buffer, &bus_component.mGain, target_gain, 1.0 / @as(f32, FADE_FRAMES));

    return bus_buffer;
}

/// Reads the next frames of one voice into voice_buffer and returns how many were read. Starts the fade of a voice that
/// has just been orphaned, and queues the destroy of one that reached the end without looping
fn ReadVoice(self: *AudioManager, engine_context: *EngineContext, voice_id: Voice.Type, voice_buffer: []f32) !u64 {
    const voice_state = self.GetVoiceState(voice_id);

    //it has lost what it was playing from, so it fades out what it played last rather than being cut off
    if (voice_state == .Orphaned) {
        try self.StartFade(engine_context, voice_id);
    }

    //fetched after StartFade, which adds to this manager's storage and so can move it
    const voice_component = self.GetComponent(VoiceComponent, voice_id).?;

    const asset_id, const pitch, const loop = switch (voice_state) {
        .Attached => |source_component| .{ source_component.mAudioAsset.mID, source_component.mPitch, source_component.mLoop },
        .Detached => .{
            self.GetComponent(VoiceAssetComponent, voice_id).?.mAsset.mID,
            self.GetComponent(VoicePitchComponent, voice_id).?.mPitch,
            false,
        },
        .Orphaned => .{ voice_component.mAssetID, voice_component.mLastPitch, false },
    };
    voice_component.mAssetID = asset_id;
    voice_component.mLastPitch = pitch;

    const bus_id = switch (voice_state) {
        .Attached => |source_component| source_component.mBus.mID,
        .Detached, .Orphaned => voice_component.mBusID,
    };
    voice_component.mBusID = bus_id;

    //its bus is paused and has faded out: read nothing, so the cursor stays put until the bus is unpaused
    if (self.IsBusHeld(self.ResolveBus(bus_id))) return 0;

    //fetched every update rather than kept, since a hot reload can swap the asset out between updates.
    //loading an asset only touches the asset manager's storage, so the component pointers above stay valid.
    //asked of the asset manager by id rather than through a handle: an unset handle has no manager pointer, and the
    //asset manager answers an unset id with its default sound
    const audio_asset = try engine_context.mAssetManager.GetAsset(engine_context, AudioAsset, asset_id);
    const frames_read = AudioMath.Read(AUDIO_CHANNELS, audio_asset.GetSamples(), voice_buffer, &voice_component.mCursor, pitch, loop);

    if (frames_read < voice_buffer.len / AUDIO_CHANNELS) {
        try self.DeleteVoice(engine_context, voice_id);
    }
    return frames_read;
}

/// Which kind of voice this is, and for an attached voice the AudioComponent it plays from. An attached voice is
/// orphaned once its source entity or AudioComponent is gone or the component's token has moved on (StopVoices, or a
/// copy of the component: a cleared and re-copied world keeps its entity ids, but every copied component starts at
/// token 0). It stays orphaned from then on, since its source is only ever looked at again to find it gone
fn GetVoiceState(self: *AudioManager, voice_id: Voice.Type) VoiceState {
    const voice_component = self.GetComponent(VoiceComponent, voice_id).?;

    const source = voice_component.mSource;
    if (!source.IsIDValid()) return .Detached;
    if (!source.IsActive()) return .Orphaned;
    const source_component = source.GetComponent(AudioComponent) orelse return .Orphaned;
    if (source_component.mVoiceToken != voice_component.mToken) return .Orphaned;
    return .{ .Attached = source_component };
}

/// Runs the voice and bus destroys queued this frame: the manager events hand each one to the ECS as a destroy, then
/// the ECS events actually free it
pub fn ProcessDestroyedVoices(self: *AudioManager, engine_context: *EngineContext) !void {
    var callback_list: std.DoublyLinkedList = .{};
    try self.ProcessEvents(EventData, .EndOfFrame, engine_context, &callback_list);

    //takes a destroyed bus's UUID out of the map while it can still be read
    var uuid_callback = ECSManagerT.ECSEventCallback{ .mCtx = self, .mCallbackFn = Core.RemoveDestroyedUUID };
    callback_list.append(&uuid_callback.mNode);
    defer callback_list.remove(&uuid_callback.mNode);
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
        .DestroyBus => |e| {
            //the ECS queues the destroy of every bus under it too
            if (self.mECSManager.IsActiveEntity(e.Bus.mID)) {
                try self.mECSManager.DestroyEntity(engine_context, e.Bus.mID);
            }
        },
        .Default => unreachable,
    }
    return .Continue;
}
