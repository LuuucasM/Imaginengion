//! A script's variables (Scripts/ScriptValues.zig): saved by name and read back, an entity by its UUID; given their own
//! copy with their object (Play's world copy, Duplicate) and pointed at the right objects; and carried over to a new
//! build of the script by name. No DLL is built: the scripts here are exported in-process (ScriptExport.Exports) and
//! put straight onto an asset, the way a loaded script's DLL would be.
//! Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const WorldManager = @import("../../Core/WorldManager.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const AssetHandle = @import("../../ECSObjects/AssetHandle.zig");
const ECSObject = @import("../../ECSObjects/ECSObject.zig");
const Assets = @import("../../ECSComponents/AComponents.zig");
const ScriptAsset = Assets.ScriptAsset;
const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const ScriptComponent = EntityComponents.ScriptComponent;
const OnUpdateScript = EntityComponents.OnUpdateScript;
const OnCollisionBeginScript = EntityComponents.OnCollisionBeginScript;
const UntypedScriptTag = EntityComponents.UntypedScriptTag;
const ScriptABI = @import("../../Scripts/ScriptABI.zig");
const ScriptExport = @import("../../Scripts/ScriptExport.zig");
const ScriptValues = @import("../../Scripts/ScriptValues.zig");
const CollisionInfo = @import("../../Physics/Collisions.zig").CollisionInfo;
const Vec3 = @import("../../Math/MathTypes.zig").Vec3;

/// A script that chases something, with one variable of most kinds
const Chaser = struct {
    mTarget: Entity = .uninit,
    mSpeed: f32 = 7.0,
    mMode: enum { Chase, Wait } = .Chase,
    mOffset: Vec3(f32) = .{ .x = 0, .y = 1, .z = 0 },

    pub fn OnUpdate(_: *@This(), _: *EngineContext, _: Entity) ScriptABI.ScriptResult {
        return .Continue;
    }
};
const ChaserExports = ScriptExport.Exports(Chaser, "Chaser");

/// Chaser after an edit: mSpeed kept, mMode's values reordered with one added, mOffset made a f32 and mTarget gone, a
/// new variable, and a second hook
const ChaserEdited = struct {
    mMode: enum { Idle, Wait, Chase } = .Idle,
    mSpeed: f32 = 1.0,
    mOffset: f32 = 0.5,
    mJumps: u32 = 3,

    pub fn OnUpdate(_: *@This(), _: *EngineContext, _: Entity) ScriptABI.ScriptResult {
        return .Continue;
    }
    pub fn OnCollisionBegin(_: *@This(), _: *EngineContext, _: Entity, _: Entity, _: *const CollisionInfo) ScriptABI.ScriptResult {
        return .Continue;
    }
};
const ChaserEditedExports = ScriptExport.Exports(ChaserEdited, "ChaserEdited");

/// A scene script, to put on an entity by mistake
const SceneRule = struct {
    pub fn OnSceneStart(_: *@This(), _: *EngineContext, _: Scene) ScriptABI.ScriptResult {
        return .Continue;
    }
};
const SceneRuleExports = ScriptExport.Exports(SceneRule, "SceneRule");

const TestWorlds = struct {
    mEngineContext: *EngineContext,
    mScene: Scene = .uninit,

    fn Init() !*TestWorlds {
        const self = try std.heap.page_allocator.create(TestWorlds);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        //UUIDs are drawn from the context's Io, which forwards to this
        engine_context._Internal.ThreadedIO = std.Io.Threaded.init(engine_context._Internal.EngineGPA.allocator(), .{
            .concurrent_limit = .nothing,
            .async_limit = .nothing,
        });
        try engine_context.mAssetManager.Init(engine_context);
        try engine_context.mGameWorld.Init(engine_context.EngineAllocator());
        try engine_context.mSimulateWorld.Init(engine_context.EngineAllocator());
        self.mScene = try engine_context.mGameWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
        return self;
    }

    fn Deinit(self: *TestWorlds) void {
        const engine_context = self.mEngineContext;
        const engine_allocator = engine_context.EngineAllocator();
        //the scripts give their variables back to the assets first
        engine_context.mSimulateWorld.Deinit(engine_context);
        engine_context.mGameWorld.Deinit(engine_context);
        engine_context.mSerializer.Deinit(engine_allocator);

        const asset_manager = &engine_context.mAssetManager;
        asset_manager.mECSManager.Deinit(engine_context);
        asset_manager.mUUIDToWorldID.deinit(engine_allocator);
        asset_manager.mEventManager.Deinit(engine_allocator);
        asset_manager.mCWDPath.deinit(engine_allocator);

        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    /// A loaded script asset running `info`, as if its DLL had handed it over. The handle is the caller's reference
    fn ScriptAssetFor(self: *TestWorlds, info: *const ScriptABI.ScriptInfo) !AssetHandle {
        const engine_context = self.mEngineContext;
        const asset_manager = &engine_context.mAssetManager;
        const engine_allocator = engine_context.EngineAllocator();
        const asset_id = try asset_manager.mECSManager.CreateEntity(engine_allocator);
        _ = try asset_manager.mECSManager.AddComponent(engine_allocator, asset_id, Assets.AssetMetaData{ .mRefs = 1 });
        var file_meta_data = Assets.FileMetaData{ .mPathType = .Prj };
        _ = try file_meta_data.mRelPath.print(engine_allocator, "scripts/Chaser.zig", .{});
        _ = try asset_manager.mECSManager.AddComponent(engine_allocator, asset_id, file_meta_data);
        _ = try asset_manager.mECSManager.AddComponent(engine_allocator, asset_id, ScriptAsset{ ._Info = info });
        return .{ .mID = asset_id, .mManager = asset_manager };
    }

    /// An entity with a script running `handle` (which keeps a reference of its own), and the script child
    fn EntityWithScript(self: *TestWorlds, handle: AssetHandle) !struct { Entity, Entity } {
        const engine_context = self.mEngineContext;
        const entity = try self.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
        handle.RetainAsset();
        const script = try ECSObject.Core(Entity).AddScript(entity, engine_context, handle);
        return .{ entity, script };
    }
};

fn ChaserOf(script: Entity) *Chaser {
    const instance = ScriptValues.InstanceOf(script.GetComponent(ScriptComponent).?).?;
    return @ptrCast(@alignCast(instance.mData));
}

test "a script gets its own variables and a tag for each of its hooks, or none for the wrong kind of object" {
    const worlds = try TestWorlds.Init();
    defer worlds.Deinit();

    var handle = try worlds.ScriptAssetFor(&ChaserExports.info);
    defer handle.ReleaseAsset();
    _, const script = try worlds.EntityWithScript(handle);
    try std.testing.expect(script.HasComponent(OnUpdateScript));
    try std.testing.expect(!script.HasComponent(OnCollisionBeginScript));
    try std.testing.expectEqual(@as(f32, 7.0), ChaserOf(script).mSpeed);

    //a scene script on an entity has nothing to run
    std.testing.log_level = .err;
    defer std.testing.log_level = .warn;
    var scene_handle = try worlds.ScriptAssetFor(&SceneRuleExports.info);
    defer scene_handle.ReleaseAsset();
    _, const wrong = try worlds.EntityWithScript(scene_handle);
    try std.testing.expect(wrong.HasComponent(UntypedScriptTag));
}

test "a script's variables are saved by name and read back, an entity once it is found by its UUID" {
    const worlds = try TestWorlds.Init();
    defer worlds.Deinit();
    const engine_context = worlds.mEngineContext;
    const engine_allocator = engine_context.EngineAllocator();

    var handle = try worlds.ScriptAssetFor(&ChaserExports.info);
    defer handle.ReleaseAsset();
    const ball = try worlds.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
    _, const script = try worlds.EntityWithScript(handle);
    const chaser = ChaserOf(script);
    chaser.mTarget = ball;
    chaser.mSpeed = 3.5;
    chaser.mMode = .Wait;
    chaser.mOffset.z = 2;

    var out: std.Io.Writer.Allocating = .init(engine_allocator);
    defer out.deinit();
    var write_stream: std.json.Stringify = .{ .writer = &out.writer };
    const instance = ScriptValues.InstanceOf(script.GetComponent(ScriptComponent).?).?;
    try ScriptValues.Write(instance.mInfo, instance.mData, &write_stream);

    const parsed = try std.json.parseFromSlice(std.json.Value, engine_allocator, out.written(), .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("Wait", parsed.value.object.get("mMode").?.string);

    _, const loaded = try worlds.EntityWithScript(handle);
    try ScriptValues.Read(engine_context, loaded, parsed.value);
    //the entity is set once it is looked for
    try std.testing.expectEqual(Entity.NullObject, ChaserOf(loaded).mTarget.mID);
    engine_context.mSerializer.ResolveUUIDs();

    const read = ChaserOf(loaded);
    try std.testing.expectEqual(ball.mID, read.mTarget.mID);
    try std.testing.expectEqual(@as(f32, 3.5), read.mSpeed);
    try std.testing.expectEqual(.Wait, read.mMode);
    try std.testing.expectEqual(@as(f32, 2), read.mOffset.z);
}

test "Play's copy of the world gives each script its own variables, pointing into the copy" {
    const worlds = try TestWorlds.Init();
    defer worlds.Deinit();
    const engine_context = worlds.mEngineContext;
    const sim_world = &engine_context.mSimulateWorld;

    var handle = try worlds.ScriptAssetFor(&ChaserExports.info);
    defer handle.ReleaseAsset();
    const ball = try worlds.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
    _, const script = try worlds.EntityWithScript(handle);
    ChaserOf(script).mTarget = ball;
    ChaserOf(script).mSpeed = 2;

    try engine_context.mGameWorld.Copy(engine_context, sim_world);

    const sim_chaser = ChaserOf(sim_world.GetEntity(script.mID));
    try std.testing.expect(sim_chaser != ChaserOf(script));
    try std.testing.expectEqual(@as(f32, 2), sim_chaser.mSpeed);
    try std.testing.expectEqual(ball.mID, sim_chaser.mTarget.mID);
    try std.testing.expectEqual(sim_world, sim_chaser.mTarget.mManager);

    //played with, the original is left as it was
    sim_chaser.mSpeed = 9;
    try std.testing.expectEqual(@as(f32, 2), ChaserOf(script).mSpeed);
}

test "a duplicate's script points at the duplicate's own child, and keeps pointing at anything outside it" {
    const worlds = try TestWorlds.Init();
    defer worlds.Deinit();
    const engine_context = worlds.mEngineContext;

    var handle = try worlds.ScriptAssetFor(&ChaserExports.info);
    defer handle.ReleaseAsset();
    const entity, const script = try worlds.EntityWithScript(handle);
    const child = try entity.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    ChaserOf(script).mTarget = child;
    ChaserOf(script).mSpeed = 4;

    const copy = try entity.Duplicate(engine_context);
    var copy_scripts = copy.GetIterator(.Script);
    const copy_chaser = ChaserOf(copy_scripts.next().?);
    var copy_children = copy.GetIterator(.Child);
    const copy_child = copy_children.next().?;
    try std.testing.expectEqual(@as(f32, 4), copy_chaser.mSpeed);
    try std.testing.expectEqual(copy_child.mID, copy_chaser.mTarget.mID);

    //something outside what was copied stays the same thing
    const outside = try worlds.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
    ChaserOf(script).mTarget = outside;
    const second = try entity.Duplicate(engine_context);
    var second_scripts = second.GetIterator(.Script);
    try std.testing.expectEqual(outside.mID, ChaserOf(second_scripts.next().?).mTarget.mID);
}

test "a new build of a script keeps the variables still in it by name, an enum by its value's name" {
    var old_value: Chaser = .{ .mSpeed = 3, .mMode = .Wait, .mOffset = .{ .x = 1, .y = 2, .z = 3 } };
    var new_value: ChaserEdited = .{};
    ScriptValues.CarryOver(&ChaserExports.info, @ptrCast(&old_value), &ChaserEditedExports.info, @ptrCast(&new_value));

    try std.testing.expectEqual(@as(f32, 3), new_value.mSpeed);
    try std.testing.expectEqual(.Wait, new_value.mMode);
    //another kind now, so its default
    try std.testing.expectEqual(@as(f32, 0.5), new_value.mOffset);
    try std.testing.expectEqual(@as(u32, 3), new_value.mJumps);
}
