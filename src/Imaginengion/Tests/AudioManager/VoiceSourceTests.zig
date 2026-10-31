//! Every object type (Entity, Scene, Player, GameContext) can hold an AudioComponent and play it. Voices only, through
//! AudioManager.InitMixer: no sound card needed. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const Player = @import("../../ECSObjects/Player.zig");
const GameContext = @import("../../ECSObjects/GameContext.zig");
const VComponents = @import("../../ECSComponents/VComponents.zig");
const VoiceComponent = VComponents.VoiceComponent;
const VoiceFadeComponent = VComponents.VoiceFadeComponent;
const BusComponent = VComponents.BusComponent;
const AudioManager = @import("../../AudioManager/AudioManager.zig");
const Bus = @import("../../ECSObjects/Bus.zig");
const AudioComponent = @import("../../ECSComponents/Shared/AudioComponent.zig");
const ObjectRef = @import("../../ECSComponents/Entity/ObjectRefComponent.zig").Ref;

fn InitEngine() !*EngineContext {
    const engine_context = try std.heap.page_allocator.create(EngineContext);
    engine_context.* = .{};
    engine_context._Internal.ThreadedIO = std.Io.Threaded.init(engine_context._Internal.EngineGPA.allocator(), .{
        .concurrent_limit = .nothing,
        .async_limit = .nothing,
    });
    try engine_context.mEditorWorld.Init(engine_context);
    try engine_context.mAudioManager.InitMixer(engine_context);
    return engine_context;
}

fn DeinitEngine(engine_context: *EngineContext) void {
    engine_context.mEditorWorld.Deinit(engine_context);
    engine_context.mAudioManager.DeinitMixer(engine_context);
    engine_context.mSerializer.Deinit(engine_context.EngineAllocator());
    _ = engine_context._Internal.EngineGPA.deinit();
    std.heap.page_allocator.destroy(engine_context);
}

test "every object type plays its AudioComponent as an attached voice, and StopAudio stops it" {
    const engine_context = try InitEngine();
    defer DeinitEngine(engine_context);
    const world = &engine_context.mEditorWorld;

    const scene = try world.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const sources = .{
        try scene.CreateEntity(engine_context, Entity.DefaultConfig),
        scene,
        try world.CreatePlayer(engine_context, Player.DefaultConfig),
        try world.CreateGameContext(engine_context, GameContext.DefaultConfig),
    };
    inline for (sources) |source| {
        _ = try source.AddComponent(engine_context, AudioComponent{});
        const voice = (try source.PlayAudio(engine_context)).?;

        const voice_source = voice.GetComponent(VoiceComponent).?.mSource.?;
        try std.testing.expectEqual(std.meta.activeTag(ObjectRef.Of(source)), std.meta.activeTag(voice_source));
        const source_id = switch (voice_source) {
            inline else => |object| object.mID,
        };
        try std.testing.expectEqual(source.mID, source_id);

        const audio_component = source.GetComponent(AudioComponent).?;
        try std.testing.expect(audio_component.mVoiceToken != 0);
        source.StopAudio();
        try std.testing.expectEqual(0, audio_component.mVoiceToken);
    }
}

test "the mix reaches each object type's AudioComponent, and fades out a voice whose source stopped" {
    const engine_context = try InitEngine();
    defer DeinitEngine(engine_context);
    const world = &engine_context.mEditorWorld;
    const audio = &engine_context.mAudioManager;
    //held: paused and already faded out, so the mix reads no asset and needs no asset manager
    const master = audio.GetMasterBus();
    master.SetPaused(true);
    master.GetComponentMut(BusComponent).?.mGain = 0;

    const scene = try world.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const sources = .{
        try scene.CreateEntity(engine_context, Entity.DefaultConfig),
        scene,
        try world.CreatePlayer(engine_context, Player.DefaultConfig),
        try world.CreateGameContext(engine_context, GameContext.DefaultConfig),
    };
    var voices: [sources.len]@import("../../ECSObjects/Voice.zig") = undefined;
    inline for (sources, 0..) |source, i| {
        _ = try source.AddComponent(engine_context, AudioComponent{});
        voices[i] = (try source.PlayAudio(engine_context)).?;
        //its token moves on, so the mix finds it orphaned
        source.StopAudio();
    }

    //the fade is started inside the mix, with VoiceFadeComponent locked: it waits, and lands as the mix ends
    try engine_context.mSystems.RunSystem(AudioManager.Mix, engine_context, .{audio});
    for (voices) |voice| try std.testing.expect(voice.HasComponent(VoiceFadeComponent));
}

const PlaysInARun = struct {
    pub const Name = "PlaysInARun";

    pub fn Run(engine_context: *EngineContext, source: Entity, master: Bus, bus: *Bus) !void {
        const voice = (try source.PlayAudio(engine_context)).?;
        //made in the middle of a run, so it waits, and reads as made
        try std.testing.expect(voice.HasComponent(VoiceComponent));
        try std.testing.expectEqual(@as(usize, 1), engine_context.mAudioManager.mECSManager.NumWithComponent(VoiceComponent));
        try std.testing.expectEqual(@as(usize, 0), engine_context.mAudioManager.mECSManager.mComponentManager.NumWithComponent(VoiceComponent));
        bus.* = try master.CreateChild(engine_context, .Entity, .{ .bAddVolume = true, .bAddName = true, .bAddUUID = true });
        try std.testing.expect(bus.HasComponent(BusComponent));
    }
};

test "a sound played and a bus made in the middle of a run land when it ends" {
    const engine_context = try InitEngine();
    defer DeinitEngine(engine_context);
    const world = &engine_context.mEditorWorld;
    const scene = try world.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const source = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try source.AddComponent(engine_context, AudioComponent{});

    var bus: Bus = undefined;
    const audio = &engine_context.mAudioManager;
    try engine_context.mSystems.RunSystem(PlaysInARun, engine_context, .{ source, audio.GetMasterBus(), &bus });

    try std.testing.expectEqual(@as(usize, 1), audio.mECSManager.NumWithComponent(VoiceComponent));
    try std.testing.expect(audio.GetBusByUUID(bus.GetUUID()) != null);
}
