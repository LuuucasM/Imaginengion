//! The systems layer (ECS/Systems.zig): while a run goes on every ECS it knows holds its changes, they land when the
//! last run ends, and it hands back what Run returns. Run with `zig build test-engine`.
const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig");
const ECS = @import("../../ECS/ECSManager.zig");
const Systems = @import("../../ECS/Systems.zig");
const GroupQuery = ECS.GroupQuery;

const Position = struct {
    pub const Name: []const u8 = "Position";
    pub const Ind: usize = ECS.BuiltinComponentCount;
    x: f32 = 0,
    pub fn Deinit(_: *Position, _: *EngineContext) void {}
};

const Velocity = struct {
    pub const Name: []const u8 = "Velocity";
    pub const Ind: usize = ECS.BuiltinComponentCount + 1;
    x: f32 = 0,
    pub fn Deinit(_: *Velocity, _: *EngineContext) void {}
};

const Health = struct {
    pub const Name: []const u8 = "Health";
    pub const Ind: usize = ECS.BuiltinComponentCount + 2;
    mHP: u32 = 100,
    pub fn Deinit(_: *Health, _: *EngineContext) void {}
};

const Gravity = struct {
    pub const Name: []const u8 = "Gravity";
    pub const Ind: usize = ECS.BuiltinComponentCount;
    y: f32 = -9.8,
    pub fn Deinit(_: *Gravity, _: *EngineContext) void {}
};

const Weather = struct {
    pub const Name: []const u8 = "Weather";
    pub const Ind: usize = ECS.BuiltinComponentCount + 1;
    mRain: bool = false,
    pub fn Deinit(_: *Weather, _: *EngineContext) void {}
};

/// what the systems below go through: bodies, and the scenes they are in
const BodyECS = ECS.ECSManager(u32, &[_]type{ Position, Velocity, Health }, "SystemsLayerBodyECS");
const SceneECS = ECS.ECSManager(u32, &[_]type{ Gravity, Weather }, "SystemsLayerSceneECS");

/// Two body ECSs and two scene ECSs, the layer, and the minimal EngineContext they need (not Init'd: the ECSs only ask
/// it for the engine allocator)
const TestLayer = struct {
    mEngineContext: *EngineContext,
    mSystems: Systems = .empty,
    mBodies: BodyECS = .empty,
    mOtherBodies: BodyECS = .empty,
    mScene: SceneECS = .empty,
    mOtherScene: SceneECS = .empty,

    fn Init() !*TestLayer {
        const self = try std.heap.page_allocator.create(TestLayer);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        self.mEngineContext.* = .{};
        const engine_allocator = self.mEngineContext.EngineAllocator();
        try self.mBodies.Init(engine_allocator);
        try self.mOtherBodies.Init(engine_allocator);
        try self.mScene.Init(engine_allocator);
        try self.mOtherScene.Init(engine_allocator);
        try self.mSystems.Register(engine_allocator, &self.mBodies);
        try self.mSystems.Register(engine_allocator, &self.mOtherBodies);
        try self.mSystems.Register(engine_allocator, &self.mScene);
        try self.mSystems.Register(engine_allocator, &self.mOtherScene);
        return self;
    }

    fn Deinit(self: *TestLayer) !void {
        const engine_context = self.mEngineContext;
        self.mSystems.Deinit(engine_context.EngineAllocator());
        self.mBodies.Deinit(engine_context);
        self.mOtherBodies.Deinit(engine_context);
        self.mScene.Deinit(engine_context);
        self.mOtherScene.Deinit(engine_context);
        const leak_check = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
        try std.testing.expect(leak_check == .ok);
    }

    fn NewBody(self: *TestLayer) !u32 {
        return try self.mBodies.CreateEntity(self.mEngineContext.EngineAllocator());
    }
};

/// What the systems below saw while they ran, for the tests to check afterwards
const Seen = struct {
    mPositionsDuring: usize = 0,
    mStagedVisible: bool = false,
    mPositionsAfterInner: usize = 0,
};

//----------------what lands, and what comes back----------------

const AddsPositions = struct {
    pub const Name = "AddsPositions";

    pub fn Run(engine_context: *EngineContext, bodies: *BodyECS, seen: *Seen) !void {
        const entity_id = try bodies.CreateEntity(engine_context.EngineAllocator());
        _ = try bodies.AddComponent(engine_context, entity_id, Position{ .x = 3 });
        seen.mStagedVisible = bodies.HasComponent(Position, entity_id);
        seen.mPositionsDuring = bodies.mComponentManager.NumWithComponent(Position);
    }
};

test "what a run adds lands once it is done" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    var seen: Seen = .{};

    try layer.mSystems.RunSystem(AddsPositions, layer.mEngineContext, .{ &layer.mBodies, &seen });

    try std.testing.expect(seen.mStagedVisible);
    try std.testing.expectEqual(@as(usize, 0), seen.mPositionsDuring);
    try std.testing.expectEqual(@as(usize, 1), layer.mBodies.NumWithComponent(Position));
}

const Counts = struct {
    pub const Name = "Counts";

    pub fn Run(_: *EngineContext, bodies: *BodyECS, extra: u32) u32 {
        return @as(u32, @intCast(bodies.NumWithComponent(Position))) + extra;
    }
};

const FailsAfterAdding = struct {
    pub const Name = "FailsAfterAdding";

    pub fn Run(engine_context: *EngineContext, bodies: *BodyECS) !u32 {
        const entity_id = try bodies.CreateEntity(engine_context.EngineAllocator());
        _ = try bodies.AddComponent(engine_context, entity_id, Position{});
        return error.SystemFailed;
    }
};

test "what Run returns comes back, and so does its error" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const body = try layer.NewBody();
    _ = try layer.mBodies.AddComponent(layer.mEngineContext, body, Position{});

    try std.testing.expectEqual(@as(u32, 11), try layer.mSystems.RunSystem(Counts, layer.mEngineContext, .{ &layer.mBodies, 10 }));

    try std.testing.expectError(error.SystemFailed, layer.mSystems.RunSystem(FailsAfterAdding, layer.mEngineContext, .{&layer.mBodies}));
    //what it added before failing still landed
    try std.testing.expectEqual(@as(usize, 2), layer.mBodies.NumWithComponent(Position));
}

const HoldsPositions = struct {
    pub const Name = "HoldsPositions";

    pub fn Run(engine_context: *EngineContext, layer: *TestLayer, seen: *Seen) !void {
        try layer.mSystems.RunSystem(AddsPositions, engine_context, .{ &layer.mBodies, seen });
        seen.mPositionsAfterInner = layer.mBodies.mComponentManager.NumWithComponent(Position);
    }
};

test "a run inside another leaves the landing to the outer one" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    var seen: Seen = .{};

    try layer.mSystems.RunSystem(HoldsPositions, layer.mEngineContext, .{ layer, &seen });

    try std.testing.expectEqual(@as(usize, 0), seen.mPositionsAfterInner);
    try std.testing.expectEqual(@as(usize, 1), layer.mBodies.NumWithComponent(Position));
}

const HoldsEverywhere = struct {
    pub const Name = "HoldsEverywhere";

    pub fn Run(engine_context: *EngineContext, layer: *TestLayer, body: u32, other_body: u32, scene: u32) !void {
        const position = try layer.mBodies.AddComponent(engine_context, body, Position{});
        position.x = 5;
        _ = try layer.mBodies.AddComponent(engine_context, body, Velocity{});
        _ = try layer.mOtherBodies.AddComponent(engine_context, other_body, Health{});
        _ = try layer.mScene.AddComponent(engine_context, scene, Gravity{});

        //each reads as added, and queries find it, but it isn't in its storage yet
        try std.testing.expect(layer.mBodies.HasComponent(Velocity, body));
        try std.testing.expect(layer.mOtherBodies.HasComponent(Health, other_body));
        try std.testing.expect(layer.mScene.HasComponent(Gravity, scene));
        try std.testing.expectEqual(@as(usize, 1), layer.mBodies.NumWithComponent(Velocity));
        try std.testing.expectEqual(@as(usize, 0), layer.mBodies.mComponentManager.NumWithComponent(Velocity));
        try std.testing.expectEqual(@as(usize, 1), layer.mOtherBodies.NumWithComponent(Health));
        try std.testing.expectEqual(@as(usize, 1), layer.mScene.NumWithComponent(Gravity));
    }
};

test "while a run goes on every ECS holds its adds, and they land when it ends" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const engine_allocator = layer.mEngineContext.EngineAllocator();
    const body = try layer.NewBody();
    const other_body = try layer.mOtherBodies.CreateEntity(engine_allocator);
    const scene = try layer.mScene.CreateEntity(engine_allocator);

    try layer.mSystems.RunSystem(HoldsEverywhere, layer.mEngineContext, .{ layer, body, other_body, scene });

    try std.testing.expectEqual(@as(usize, 1), layer.mBodies.NumWithComponent(Velocity));
    try std.testing.expectEqual(@as(usize, 1), layer.mOtherBodies.NumWithComponent(Health));
    try std.testing.expectEqual(@as(usize, 1), layer.mScene.NumWithComponent(Gravity));
    //written while it waited, and landed with it
    try std.testing.expectEqual(@as(f32, 5), layer.mBodies.GetComponent(Position, body).?.x);
}

const HoldsChanges = struct {
    pub const Name = "HoldsChanges";

    pub fn Run(engine_context: *EngineContext, layer: *TestLayer, keeps: u32, goes: u32) !void {
        const bodies = &layer.mBodies;
        try bodies.RemoveComponent(engine_context, keeps, BodyECS.ComponentInd(Health));
        try bodies.DestroyEntity(engine_context, goes);
        try std.testing.expect(bodies.HasComponent(Health, keeps));
        try std.testing.expect(bodies.IsActiveEntity(goes));
        try std.testing.expect(!bodies.CanChangeStorage(BodyECS.ComponentInd(Velocity)));

        //a tag has no storage to move, and parents and children are linked as they are asked for
        _ = try bodies.AddComponent(engine_context, keeps, ECS.MainObjectComponent{});
        try std.testing.expectEqual(@as(usize, 1), bodies.NumWithComponent(ECS.MainObjectComponent));
        const child = try bodies.AddChild(engine_context, keeps, .Entity);
        try std.testing.expectEqual(keeps, bodies.GetComponent(BodyECS.ChildComponent, child).?.mParent);
    }
};

test "while a run goes on removals and destroys wait, tags and parents and children don't" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const engine_context = layer.mEngineContext;
    const keeps = try layer.NewBody();
    const goes = try layer.NewBody();
    _ = try layer.mBodies.AddComponent(engine_context, keeps, Health{});

    try layer.mSystems.RunSystem(HoldsChanges, engine_context, .{ layer, keeps, goes });

    try std.testing.expect(!layer.mBodies.HasComponent(Health, keeps));
    try std.testing.expect(!layer.mBodies.IsActiveEntity(goes));
}

const AddsInAnotherRun = struct {
    pub const Name = "AddsInAnotherRun";

    pub fn Run(engine_context: *EngineContext, bodies: *BodyECS, body: u32) !void {
        _ = try bodies.AddComponent(engine_context, body, Position{});
    }
};

const OuterAddsInner = struct {
    pub const Name = "OuterAddsInner";

    pub fn Run(engine_context: *EngineContext, layer: *TestLayer, body: u32) !void {
        try layer.mSystems.RunSystem(AddsInAnotherRun, engine_context, .{ &layer.mBodies, body });
        //the inner run has ended, but this one hasn't
        try std.testing.expectEqual(@as(usize, 0), layer.mBodies.mComponentManager.NumWithComponent(Position));
    }
};

test "changes wait for the outermost run to end" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const body = try layer.NewBody();

    try layer.mSystems.RunSystem(OuterAddsInner, layer.mEngineContext, .{ layer, body });

    try std.testing.expectEqual(@as(usize, 1), layer.mBodies.NumWithComponent(Position));
    try std.testing.expectEqual(@as(u32, 0), layer.mSystems.mRunDepth);
}

/// Runs a system when a scene's component comes off, as landing it: what that system adds goes in an ECS the landing has
/// already been past
const LandingChain = struct {
    mLayer: *TestLayer,
    mBody: u32,

    fn OnRemoval(ctx: *anyopaque, engine_context: *EngineContext, _: SceneECS.ECSEventDataT.EventT) anyerror!void {
        const self: *LandingChain = @ptrCast(@alignCast(ctx));
        try self.mLayer.mSystems.RunSystem(AddsInAnotherRun, engine_context, .{ &self.mLayer.mBodies, self.mBody });
    }
};

const RemovesGravity = struct {
    pub const Name = "RemovesGravity";

    pub fn Run(engine_context: *EngineContext, scene_ecs: *SceneECS, scene: u32) !void {
        try scene_ecs.RemoveComponent(engine_context, scene, SceneECS.ComponentInd(Gravity));
    }
};

test "what landing sets off lands too, even in an ECS it has already been past" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const engine_context = layer.mEngineContext;
    const body = try layer.NewBody();
    const scene = try layer.mScene.CreateEntity(engine_context.EngineAllocator());
    _ = try layer.mScene.AddComponent(engine_context, scene, Gravity{});

    var chain = LandingChain{ .mLayer = layer, .mBody = body };
    layer.mScene.SetRemovalHook(.{ .mCtx = &chain, .mFn = LandingChain.OnRemoval });
    try layer.mSystems.RunSystem(RemovesGravity, engine_context, .{ &layer.mScene, scene });

    try std.testing.expect(!layer.mScene.HasComponent(Gravity, scene));
    try std.testing.expectEqual(@as(usize, 1), layer.mBodies.NumWithComponent(Position));
    try std.testing.expect(!layer.mSystems.mLanding);
}

test "an ECS that opts out of runs changes right away, and is left alone by them" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const body = try layer.NewBody();
    layer.mBodies.SetRunDepth(null);

    try layer.mSystems.RunSystem(OuterAddsNothing, layer.mEngineContext, .{ layer, body });

    try std.testing.expectEqual(@as(f32, 2), layer.mBodies.GetComponent(Position, body).?.x);
}

const OuterAddsNothing = struct {
    pub const Name = "OuterAddsNothing";

    pub fn Run(engine_context: *EngineContext, layer: *TestLayer, body: u32) !void {
        const position = try layer.mBodies.AddComponent(engine_context, body, Position{ .x = 2 });
        _ = position;
        //in its storage already
        try std.testing.expectEqual(@as(usize, 1), layer.mBodies.mComponentManager.NumWithComponent(Position));
    }
};

const QueriesWhileHolding = struct {
    pub const Name = "QueriesWhileHolding";

    pub fn Run(engine_context: *EngineContext, bodies: *BodyECS, landed: u32, waiting: u32) !void {
        const allocator = engine_context.EngineAllocator();
        //`landed` has a Position in storage, and gets a Velocity staged. `waiting` only has a Position staged
        _ = try bodies.AddComponent(engine_context, waiting, Position{});
        _ = try bodies.AddComponent(engine_context, landed, Velocity{});

        var positions = try bodies.GetGroup(allocator, .{ .Component = Position });
        defer positions.deinit(allocator);
        try std.testing.expectEqualSlices(u32, &.{ landed, waiting }, positions.items);

        var moving = try bodies.GetGroup(allocator, .{ .And = &.{ .{ .Component = Position }, .{ .Component = Velocity } } });
        defer moving.deinit(allocator);
        try std.testing.expectEqualSlices(u32, &.{landed}, moving.items);

        //`landed` stops matching because of what is staged, `waiting` starts to
        const has_position = GroupQuery{ .Component = Position };
        const has_velocity = GroupQuery{ .Component = Velocity };
        var still = try bodies.GetGroup(allocator, .{ .Not = .{ .mFirst = &has_position, .mSecond = &has_velocity } });
        defer still.deinit(allocator);
        try std.testing.expectEqualSlices(u32, &.{waiting}, still.items);
    }
};

test "a query finds what is staged, in every way of asking" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const engine_context = layer.mEngineContext;
    const landed = try layer.NewBody();
    const waiting = try layer.NewBody();
    _ = try layer.mBodies.AddComponent(engine_context, landed, Position{});

    try layer.mSystems.RunSystem(QueriesWhileHolding, engine_context, .{ &layer.mBodies, landed, waiting });
}
