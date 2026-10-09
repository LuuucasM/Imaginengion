const std = @import("std");
const Inspector = @import("../../UI/Inspector.zig");
const AssetHandle = @import("../../ECSObjects/AssetHandle.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const Assets = @import("../AComponents.zig");
const FileMetaData = Assets.FileMetaData;
const Entity = @import("../../ECSObjects/Entity.zig");
const Bus = @import("../../ECSObjects/Bus.zig");
const BusNameComponent = @import("../VComponents.zig").NameComponent;
const UUIDComponent = @import("../Shared/UUIDComponent.zig");
const Serializer = @import("../../Serializer/Serializer.zig");
const EngineContext = @import("../../Core/EngineContext.zig");

const ImguiManager = @import("../../Imgui/Imgui.zig");

const AudioComponent = @This();

pub const AudioType = enum(u8) {
    Audio2D = 0,
    Audio3D = 1,
};

pub const Editable: bool = true;
pub const Name: []const u8 = "AudioComponent";

//how the sound should be played. The playing itself is done by voices in the AudioManager (see PlayVoice). Attached
//voices read these live, so one component can be playing any number of voices at once and editing it changes them all
mAudioType: AudioType = .Audio2D,
mAudioAsset: AssetHandle = .uninit,
mVolume: f32 = 1.0,
mPitch: f32 = 1.0,
mLoop: bool = false,
/// The bus its voices play into. Uninit means Master, and so does a bus that has since been deleted
mBus: Bus = .uninit,

/// true: the voices this plays are attached. They read the settings above live and stop with the component (its
/// entity destroyed, it removed, or StopVoices). For sounds that belong to something: an engine hum, dialogue.
/// false: they are detached one-shots. They take a copy of the asset and volume when they start and play to the end
/// even if the entity is gone. For death screams, pickups, impacts. Can not loop, since nothing could stop them
mStopWithSource: bool = true,

/// Which batch of attached voices is this component's current one: a voice only plays while its token matches.
/// 0 until the component first plays. Not saved, and a copy starts at 0, so it can never match an older voice
mVoiceToken: u32 = 0,

/// Stops every attached voice this component started. They notice at the next mix, since their token no longer
/// matches. The next play hands the component a fresh token
pub fn StopVoices(self: *AudioComponent) void {
    self.mVoiceToken = 0;
}

pub fn Deinit(self: *AudioComponent, _: *EngineContext) void {
    self.mAudioAsset.ReleaseAsset();
}

pub fn Clone(self: *const AudioComponent, _: *EngineContext) !AudioComponent {
    var new_component = self.*;

    // the copy releases the asset itself, so it needs its own reference
    new_component.mAudioAsset.RetainAsset();

    //the original's voices are not the copy's: a re-copied world keeps its entity ids, so a copied token would let
    //old voices play from the copy
    new_component.mVoiceToken = 0;

    return new_component;
}
pub fn UIRender(self: *AudioComponent, ui: *Inspector.Builder) !void {
    try ui.Float(&self.mVolume, "Volume", .{ .Speed = 0.01, .Min = 0, .Max = 1, .Decimals = 2 });
    try ui.Float(&self.mPitch, "Pitch", .{ .Speed = 0.01, .Min = 0.1, .Max = 4, .Decimals = 2 });
    try ui.Bool(&self.mLoop, "Looping", .{});
    try ui.Bool(&self.mStopWithSource, "Stop With Source", .{});
    try ui.Enum(AudioType, &self.mAudioType, "Audio Type", .{});
    try ui.Separator();
    try ui.Asset(&self.mAudioAsset, "Audio", &.{ ".mp3", ".wav", ".flac" }, .{});

    //the buses as they are now: one added while this is shown appears the next time it is built
    var buses: std.ArrayList(Bus) = .empty;
    try BusesInOrder(ui.mEngineContext.FrameAllocator(), ui.mEngineContext.mAudioManager.GetMasterBus(), &buses);
    const names = try ui.mEngineContext.FrameAllocator().alloc([]const u8, buses.items.len);
    for (buses.items, names) |bus, *name| name.* = if (bus.GetComponent(BusNameComponent)) |bus_name| bus_name.mName.items else "Bus";
    try ui.Choice(&self.mBus, "Bus", names, &BUS_ACCESS, .{});
}

/// `bus` and every bus under it, each before the ones under it: the order the Bus dropdown lists them in
fn BusesInOrder(frame_allocator: std.mem.Allocator, bus: Bus, buses: *std.ArrayList(Bus)) !void {
    try buses.append(frame_allocator, bus);
    var children = bus.GetIterator(.Child);
    while (children.next()) |child| try BusesInOrder(frame_allocator, child, buses);
}

/// Where `target` comes in BusesInOrder from `bus`, counting on from `next`
fn BusIndex(bus: Bus, target: Bus.Type, next: *usize) ?usize {
    if (bus.mID == target) return next.*;
    next.* += 1;
    var children = bus.GetIterator(.Child);
    while (children.next()) |child| {
        if (BusIndex(child, target, next)) |index| return index;
    }
    return null;
}

/// The bus at `index` in BusesInOrder from `bus`, counting on from `next`
fn BusAt(bus: Bus, index: usize, next: *usize) ?Bus {
    if (next.* == index) return bus;
    next.* += 1;
    var children = bus.GetIterator(.Child);
    while (children.next()) |child| {
        if (BusAt(child, index, next)) |found| return found;
    }
    return null;
}

/// The bus as its place in the Bus dropdown. No bus picked (uninit) plays through Master, the first
const BUS_ACCESS = Inspector.Access{
    .Read = struct {
        fn Read(field: *anyopaque) Inspector.Value {
            const bus: *Bus = @ptrCast(@alignCast(field));
            if (bus.mID == Bus.NullObject) return .{ .Choice = 0 };
            var next: usize = 0;
            return .{ .Choice = BusIndex(bus.mManager.GetMasterBus(), bus.mID, &next) orelse 0 };
        }
    }.Read,
    .Write = struct {
        fn Write(engine_context: *EngineContext, field: *anyopaque, written: Inspector.Value) anyerror!void {
            const bus: *Bus = @ptrCast(@alignCast(field));
            var next: usize = 0;
            if (BusAt(engine_context.mAudioManager.GetMasterBus(), written.Choice, &next)) |picked| bus.* = picked;
        }
    }.Write,
};

pub fn EditorRender(self: *AudioComponent, engine_context: *EngineContext) !void {
    // Volume drag
    _ = try ImguiManager.RenderFloatDrag(&self.mVolume, "Volume", 0.01, 0.0, 1.0);

    // Pitch drag
    //a playback rate: 1 is normal, 2 is twice as fast and an octave up, 0.5 half as fast and an octave down
    _ = try ImguiManager.RenderFloatDrag(&self.mPitch, "Pitch", 0.01, 0.1, 4.0);

    // Loop toggle
    try ImguiManager.RenderBool(&self.mLoop, "Looping?");

    try ImguiManager.RenderBool(&self.mStopWithSource, "Stop With Source?");

    try ImguiManager.RenderEnum(AudioType, &self.mAudioType, "Audio Type");

    try ImguiManager.ImguiSeparator();

    try ImguiManager.RenderAssetRef(engine_context, &self.mAudioAsset, "Audio Asset", "AudioAsset");

    if (try ImguiManager.RenderBusRef(engine_context, &self.mBus, "Bus")) |new_bus| self.mBus = new_bus;
}

pub fn jsonStringify(self: *const AudioComponent, jw: anytype) !void {
    try jw.beginObject();

    try jw.objectField("AudioType");
    try jw.write(self.mAudioType);
    try jw.objectField("Audio");
    try jw.write(self.mAudioAsset);
    try jw.objectField("Volume");
    try jw.write(self.mVolume);
    try jw.objectField("Pitch");
    try jw.write(self.mPitch);
    try jw.objectField("Loop");
    try jw.write(self.mLoop);
    try jw.objectField("StopWithSource");
    try jw.write(self.mStopWithSource);

    //a bus is saved as its UUID, and turned back into the bus once the project's buses are loaded. Master is left out,
    //since a bus that is not set plays into Master anyway
    if (self.mBus.IsActive() and self.mBus.mID != self.mBus.mManager.GetMasterBus().mID) {
        if (self.mBus.GetComponent(UUIDComponent)) |uuid_component| {
            try jw.objectField("Bus");
            try jw.write(uuid_component.ID);
        }
    }

    try jw.endObject();
}

pub fn jsonParse(frame_allocator: std.mem.Allocator, reader: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!AudioComponent {
    //a key a file does not have keeps the component's default
    const FileData = struct {
        AudioType: AudioType = .Audio2D,
        Audio: AssetHandle = .uninit,
        Volume: f32 = 1.0,
        Pitch: f32 = 1.0,
        Loop: bool = false,
        StopWithSource: bool = true,
        Bus: ?u64 = null,
    };
    const file_data = try std.json.innerParse(FileData, frame_allocator, reader, options);

    if (file_data.Bus) |bus_uuid| {
        const engine_context = JsonUtils.EngineContextFromAllocator(frame_allocator);
        const serializer = &engine_context.mSerializer;
        std.debug.assert(serializer.mCurrDeserialize.requester == .Entity);
        try serializer.AddResolveReq(engine_context.EngineAllocator(), .{
            .Requester = serializer.mCurrDeserialize.requester,
            .UUID = bus_uuid,
            .Resolve = ResolveBusRef,
        });
    }

    return .{
        .mAudioType = file_data.AudioType,
        .mAudioAsset = file_data.Audio,
        .mVolume = file_data.Volume,
        .mPitch = file_data.Pitch,
        .mLoop = file_data.Loop,
        .mStopWithSource = file_data.StopWithSource,
    };
}

fn ResolveBusRef(requester: Serializer.Requester, bus_uuid: u64) bool {
    //the component may have been removed since the request was made, nothing left to resolve
    const audio_component = requester.Entity.GetComponent(AudioComponent) orelse return true;
    //AddComponent pointed mBus at the AudioManager when the parsed component was added
    const bus = audio_component.mBus.mManager.GetBusByUUID(bus_uuid) orelse return false;
    audio_component.mBus = bus;
    return true;
}
