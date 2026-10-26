//! Systems (ECS/System.zig): what a system touches is locked while it runs, its parameters are supplied by type, and a
//! world runs one across all of its ECSs. Run with `zig build test-engine`.
const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig");
const WorldManager = @import("../../Core/WorldManager.zig");
const ECS = @import("../../ECS/ECSManager.zig");
const System = @import("../../ECS/System.zig").System;

const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const EManager = @import("../../ECSManagers/EManager.zig");
const GCManager = @import("../../ECSManagers/GCManager.zig");
const PManager = @import("../../ECSManagers/PManager.zig");
const SManager = @import("../../ECSManagers/SManager.zig");
const TransformComponent = @import("../../ECSComponents/EComponents.zig").TransformComponent;
const RigidBodyComponent = @import("../../ECSComponents/EComponents.zig").RigidBodyComponent;
const SceneComponent = @import("../../ECSComponents/SComponents.zig").SceneComponent;
const NameComponent = @import("../../ECSComponents/Shared/NameComponent.zig");

const Position = struct {
    pub const Name: []const u8 = "Position";
    pub const Ind: usize = ECS.BuiltinComponentCount;

    x: f32 = 0,

    pub fn Deinit(_: *Position, _: *EngineContext) void {}
};

const Health = struct {
    pub const Name: []const u8 = "Health";
    pub const Ind: usize = ECS.BuiltinComponentCount + 1;

    mHP: u32 = 100,

    pub fn Deinit(_: *Health, _: *EngineContext) void {}
};

const TestECSManager = ECS.ECSManager(u32, &[_]type{ Position, Health }, "SystemTestECS");

/// An ECS plus the minimal EngineContext it needs, which is not Init'd: the ECS only asks it for the engine allocator
const TestECS = struct {
    mEngineContext: *EngineContext,
    mECSManager: TestECSManager,

    fn Init() !*TestECS {
        const self = try std.heap.page_allocator.create(TestECS);
        self.* = .{
            .mEngineContext = try std.heap.page_allocator.create(EngineContext),
            .mECSManager = .empty,
        };
        self.mEngineContext.* = .{};
        try self.mECSManager.Init(self.mEngineContext.EngineAllocator());
        return self;
    }

    fn Deinit(self: *TestECS) !void {
        const engine_context = self.mEngineContext;
        self.mECSManager.Deinit(engine_context);
        const leak_check = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
        try std.testing.expect(leak_check == .ok);
    }

    fn Params(self: *TestECS, seen: *Seen) TestParams {
        return .{ .mEngineContext = self.mEngineContext, .mSeen = seen };
    }
};

/// What the systems below saw while they ran, for the tests to check afterwards
const Seen = struct {
    mSliceMoved: bool = true,
    mStagedVisible: bool = false,
    mPositionsDuring: usize = 0,
    mHealthsDuring: usize = 0,
    mPositionsAfterInner: usize = 0,
    mECS: ?*TestECSManager = null,

    mAllowsPosition: bool = false,
    mAllowsHealth: bool = true,
    mAllowsHierarchy: bool = false,
    mAllowsTag: bool = false,
    mAllowsInUnchecked: bool = false,
    mInnerAllowsPosition: bool = true,
    mInnerAllowsHealth: bool = false,
};

/// What the test systems take besides the ECS, which RunSystem supplies itself
const TestParams = struct {
    mEngineContext: *EngineContext,
    mSeen: *Seen,

    pub fn Get(self: TestParams, comptime T: type) T {
        if (T == *EngineContext) {
            return self.mEngineContext;
        } else if (T == *Seen) {
            return self.mSeen;
        } else {
            @compileError("the test systems can't be given a " ++ @typeName(T));
        }
    }
};

/// Holds a slice of the positions while it makes plenty more of them
const HoldsPositions = System(.{
    .Name = "HoldsPositions",
    .Reads = &.{Position},
    .Run = struct {
        fn Run(ecs: *TestECSManager, engine_context: *EngineContext, seen: *Seen) !void {
            const positions = ecs.GetComponentSlice(Position);
            var last: u32 = undefined;
            //enough to have grown the array, and moved `positions`, had they been added right away
            for (0..64) |i| {
                last = try ecs.CreateEntity(engine_context.EngineAllocator());
                _ = try ecs.AddComponent(engine_context, last, Position{ .x = @floatFromInt(i) });
            }
            seen.mStagedVisible = ecs.HasComponent(Position, last);
            seen.mPositionsDuring = ecs.NumWithComponent(Position);
            seen.mSliceMoved = ecs.GetComponentSlice(Position).ptr != positions.ptr;
        }
    }.Run,
});

test "a system can hold a slice of what it reads while it adds more of them" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const ecs = &test_ecs.mECSManager;
    var seen: Seen = .{};

    const first = try ecs.CreateEntity(test_ecs.mEngineContext.EngineAllocator());
    _ = try ecs.AddComponent(test_ecs.mEngineContext, first, Position{ .x = -1 });

    try ecs.RunSystem(test_ecs.mEngineContext, HoldsPositions, test_ecs.Params(&seen));

    //while it ran: the new ones read as there, but the array didn't take them, so the slice it held stayed good
    try std.testing.expect(!seen.mSliceMoved);
    try std.testing.expect(seen.mStagedVisible);
    try std.testing.expectEqual(@as(usize, 1), seen.mPositionsDuring);

    //once it was done they landed, and nothing is left locked
    try std.testing.expectEqual(@as(usize, 65), ecs.NumWithComponent(Position));
    try std.testing.expectEqual(@as(u32, 0), ecs.mLockTotal);
}

/// Adds a component it doesn't list, then one it does
const AddsUnlisted = System(.{
    .Name = "AddsUnlisted",
    .Reads = &.{Position},
    .Run = struct {
        fn Run(ecs: *TestECSManager, engine_context: *EngineContext, seen: *Seen) !void {
            const entity_id = try ecs.CreateEntity(engine_context.EngineAllocator());
            //first, while nothing is queued yet: not listed, so made right away
            _ = try ecs.AddComponent(engine_context, entity_id, Health{});
            seen.mHealthsDuring = ecs.NumWithComponent(Health);
            _ = try ecs.AddComponent(engine_context, entity_id, Position{});
            seen.mPositionsDuring = ecs.NumWithComponent(Position);
        }
    }.Run,
});

test "what a system doesn't list is changed right away while it runs" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const ecs = &test_ecs.mECSManager;
    var seen: Seen = .{};

    try ecs.RunSystem(test_ecs.mEngineContext, AddsUnlisted, test_ecs.Params(&seen));

    try std.testing.expectEqual(@as(usize, 1), seen.mHealthsDuring);
    try std.testing.expectEqual(@as(usize, 0), seen.mPositionsDuring);
    try std.testing.expectEqual(@as(usize, 1), ecs.NumWithComponent(Position));
}

const Fails = System(.{
    .Name = "Fails",
    .Writes = &.{Position},
    .Run = struct {
        fn Run(ecs: *TestECSManager, engine_context: *EngineContext) !void {
            const entity_id = try ecs.CreateEntity(engine_context.EngineAllocator());
            _ = try ecs.AddComponent(engine_context, entity_id, Position{});
            return error.SystemFailed;
        }
    }.Run,
});

test "a system that fails hands back its error and leaves nothing locked" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const ecs = &test_ecs.mECSManager;
    var seen: Seen = .{};

    try std.testing.expectError(error.SystemFailed, ecs.RunSystem(test_ecs.mEngineContext, Fails, test_ecs.Params(&seen)));

    try std.testing.expectEqual(@as(u32, 0), ecs.mLockTotal);
    //what it changed before failing still landed
    try std.testing.expectEqual(@as(usize, 1), ecs.NumWithComponent(Position));
}

const InnerAdd = System(.{
    .Name = "InnerAdd",
    .Writes = &.{Position},
    .Run = struct {
        fn Run(ecs: *TestECSManager, engine_context: *EngineContext) !void {
            const entity_id = try ecs.CreateEntity(engine_context.EngineAllocator());
            _ = try ecs.AddComponent(engine_context, entity_id, Position{});
        }
    }.Run,
});

const Outer = System(.{
    .Name = "Outer",
    .Reads = &.{Position},
    .Run = struct {
        fn Run(ecs: *TestECSManager, engine_context: *EngineContext, seen: *Seen) !void {
            try ecs.RunSystem(engine_context, InnerAdd, TestParams{ .mEngineContext = engine_context, .mSeen = seen });
            seen.mPositionsAfterInner = ecs.NumWithComponent(Position);
        }
    }.Run,
});

test "a system run inside another leaves the draining to the outer one" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const ecs = &test_ecs.mECSManager;
    var seen: Seen = .{};

    try ecs.RunSystem(test_ecs.mEngineContext, Outer, test_ecs.Params(&seen));

    try std.testing.expectEqual(@as(usize, 0), seen.mPositionsAfterInner);
    try std.testing.expectEqual(@as(usize, 1), ecs.NumWithComponent(Position));
}

const SeenFirst = System(.{
    .Name = "SeenFirst",
    .Run = struct {
        fn Run(seen: *Seen, ecs: *TestECSManager) void {
            seen.mECS = ecs;
        }
    }.Run,
});

const OnlyTheECS = System(.{
    .Name = "OnlyTheECS",
    .Reads = &.{Health},
    .Run = struct {
        fn Run(ecs: *TestECSManager) void {
            std.debug.assert(ecs.mLockTotal == 1);
        }
    }.Run,
});

test "a system's parameters are supplied by type, in any order" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const ecs = &test_ecs.mECSManager;
    var seen: Seen = .{};

    try ecs.RunSystem(test_ecs.mEngineContext, SeenFirst, test_ecs.Params(&seen));
    try std.testing.expectEqual(ecs, seen.mECS.?);

    //nothing but the ECS, so nothing else has to be given
    try ecs.RunSystem(test_ecs.mEngineContext, OnlyTheECS, .{});
}

//----------------the debug checks----------------

const ReadsHealthOnly = System(.{
    .Name = "ReadsHealthOnly",
    .Reads = &.{Health},
    .Run = struct {
        fn Run(ecs: *TestECSManager, seen: *Seen) void {
            seen.mInnerAllowsPosition = ecs.AllowsAccess(Position);
            seen.mInnerAllowsHealth = ecs.AllowsAccess(Health);
        }
    }.Run,
});

const ReadsPositionOnly = System(.{
    .Name = "ReadsPositionOnly",
    .Reads = &.{Position},
    .Run = struct {
        fn Run(ecs: *TestECSManager, engine_context: *EngineContext, seen: *Seen) !void {
            seen.mAllowsPosition = ecs.AllowsAccess(Position);
            seen.mAllowsHealth = ecs.AllowsAccess(Health);
            seen.mAllowsHierarchy = ecs.AllowsAccess(TestECSManager.ParentComponent) and ecs.AllowsAccess(TestECSManager.ChildComponent);
            seen.mAllowsTag = ecs.AllowsAccess(ECS.MainObjectComponent);

            var unchecked = TestECSManager.UncheckedRecord;
            ecs.EnterSystem(&unchecked);
            seen.mAllowsInUnchecked = ecs.AllowsAccess(Health);
            ecs.LeaveSystem(&unchecked);

            try ecs.RunSystem(engine_context, ReadsHealthOnly, TestParams{ .mEngineContext = engine_context, .mSeen = seen });
        }
    }.Run,
});

test "a running system may only get pointers into what it listed" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const ecs = &test_ecs.mECSManager;
    var seen: Seen = .{};

    //outside any system, everything
    try std.testing.expect(ecs.AllowsAccess(Health));

    try ecs.RunSystem(test_ecs.mEngineContext, ReadsPositionOnly, test_ecs.Params(&seen));

    try std.testing.expect(seen.mAllowsPosition);
    try std.testing.expect(!seen.mAllowsHealth);
    //the hierarchy and tags always
    try std.testing.expect(seen.mAllowsHierarchy);
    try std.testing.expect(seen.mAllowsTag);
    //engine bookkeeping inside the system runs unchecked
    try std.testing.expect(seen.mAllowsInUnchecked);
    //the innermost system is what counts: the inner one can't use what the outer one listed
    try std.testing.expect(!seen.mInnerAllowsPosition);
    try std.testing.expect(seen.mInnerAllowsHealth);

    //and everything again once it is done
    try std.testing.expect(ecs.AllowsAccess(Health));
}

test "a change can only go straight to storage that isn't locked" {
    const test_ecs = try TestECS.Init();
    defer test_ecs.Deinit() catch unreachable;
    const ecs = &test_ecs.mECSManager;

    ecs.Lock(&.{ Position, ECS.MainObjectComponent });
    try std.testing.expect(!ecs.CanChangeStorage(Position.Ind));
    try std.testing.expect(ecs.CanChangeStorage(Health.Ind));
    //a tag has no storage to move, locked or not
    try std.testing.expect(ecs.CanChangeStorage(ECS.MainObjectComponent.Ind));
    try ecs.Unlock(test_ecs.mEngineContext, &.{ Position, ECS.MainObjectComponent });
    try std.testing.expect(ecs.CanChangeStorage(Position.Ind));
}

//----------------a system on a world----------------

/// What TouchesWorld saw, and what it was given to work on
const WorldSeen = struct {
    mEntity: Entity = undefined,
    mDoomedScene: Scene = undefined,
    mTransformsBefore: usize = 0,

    mTransformLocked: bool = false,
    mSceneLocked: bool = false,
    mNameLockedEverywhere: bool = false,
    mTransformStaged: bool = false,
    mSceneWaited: bool = false,
    mEntitiesAllowRigidBody: bool = true,
    mGameContextsAllowName: bool = false,
};
var world_seen: WorldSeen = .{};

const TouchesWorld = System(.{
    .Name = "TouchesWorld",
    .Reads = &.{NameComponent},
    .Writes = &.{ TransformComponent, SceneComponent },
    .Run = struct {
        fn Run(world: *WorldManager, engine_context: *EngineContext) !void {
            const entity_ecs = &world.mEManager.mECSManager;
            world_seen.mTransformLocked = entity_ecs.mLockCounts[EManager.ECSManagerT.ComponentInd(TransformComponent)] > 0;
            world_seen.mSceneLocked = world.mSManager.mECSManager.mLockCounts[SManager.ECSManagerT.ComponentInd(SceneComponent)] > 0;
            world_seen.mNameLockedEverywhere =
                entity_ecs.mLockCounts[EManager.ECSManagerT.ComponentInd(NameComponent)] > 0 and
                world.mGCManager.mECSManager.mLockCounts[GCManager.ECSManagerT.ComponentInd(NameComponent)] > 0 and
                world.mPManager.mECSManager.mLockCounts[PManager.ECSManagerT.ComponentInd(NameComponent)] > 0 and
                world.mSManager.mECSManager.mLockCounts[SManager.ECSManagerT.ComponentInd(NameComponent)] > 0;

            //what it listed, on the ECSs that have it, and not what it didn't
            world_seen.mEntitiesAllowRigidBody = entity_ecs.AllowsAccess(RigidBodyComponent);
            world_seen.mGameContextsAllowName = world.mGCManager.mECSManager.AllowsAccess(NameComponent);

            _ = try world_seen.mEntity.AddComponent(engine_context, TransformComponent{});
            world_seen.mTransformStaged = world_seen.mEntity.HasComponent(TransformComponent) and
                entity_ecs.NumWithComponent(TransformComponent) == world_seen.mTransformsBefore;

            try world_seen.mDoomedScene.Delete(engine_context);
            world_seen.mSceneWaited = world_seen.mDoomedScene.IsActive();
        }
    }.Run,
});

const TestWorld = struct {
    mEngineContext: *EngineContext,

    fn Init() !*TestWorld {
        const self = try std.heap.page_allocator.create(TestWorld);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        self.mEngineContext.* = .{};
        try self.mEngineContext.mEditorWorld.Init(self.mEngineContext);
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        engine_context.mEditorWorld.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }
};

test "a world locks what a system touches in every one of its ECSs that has it" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const editor_world = &engine_context.mEditorWorld;

    const scene = try editor_world.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    world_seen = .{
        .mEntity = try scene.CreateEntity(engine_context, Entity.BlankConfig),
        .mDoomedScene = try editor_world.NewScene(engine_context, .GameLayer, Scene.DefaultConfig),
        .mTransformsBefore = editor_world.mEManager.mECSManager.NumWithComponent(TransformComponent),
    };

    try editor_world.RunSystem(engine_context, TouchesWorld);

    //each type locked where it lives: the transform on entities, the scene component on scenes, names on all four
    try std.testing.expect(world_seen.mTransformLocked);
    try std.testing.expect(world_seen.mSceneLocked);
    try std.testing.expect(world_seen.mNameLockedEverywhere);
    try std.testing.expect(!world_seen.mEntitiesAllowRigidBody);
    try std.testing.expect(world_seen.mGameContextsAllowName);

    //so the transform was staged and the scene's delete waited, and both happened once it was done
    try std.testing.expect(world_seen.mTransformStaged);
    try std.testing.expect(world_seen.mSceneWaited);
    try std.testing.expectEqual(world_seen.mTransformsBefore + 1, editor_world.mEManager.mECSManager.NumWithComponent(TransformComponent));
    try std.testing.expect(!world_seen.mDoomedScene.IsActive());
    try std.testing.expectEqual(@as(u32, 0), editor_world.mEManager.mECSManager.mLockTotal);
    try std.testing.expectEqual(@as(u32, 0), editor_world.mSManager.mECSManager.mLockTotal);
}
