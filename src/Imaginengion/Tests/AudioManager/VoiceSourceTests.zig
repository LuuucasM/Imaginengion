//! Every object type (Entity, Scene, Player, GameContext) can hold an AudioComponent and play it. Voices only, through
//! AudioManager.InitMixer: no sound card needed. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const Player = @import("../../ECSObjects/Player.zig");
const GameContext = @import("../../ECSObjects/GameContext.zig");
const VoiceComponent = @import("../../ECSComponents/VComponents.zig").VoiceComponent;
const AudioComponent = @import("../../ECSComponents/Shared/AudioComponent.zig");
const ObjectRef = @import("../../ECSComponents/Entity/ObjectRefComponent.zig").Ref;

fn InitEngine() !*EngineContext {
    const engine_context = try std.heap.page_allocator.create(EngineContext);
    engine_context.* = .{};
    engine_context._Internal.ThreadedIO = std.Io.Threaded.init(engine_context._Internal.EngineGPA.allocator(), .{
        .concurrent_limit = .nothing,
        .async_limit = .nothing,
    });
    try engine_context.mEditorWorld.Init(engine_context.EngineAllocator());
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
