//! The systems layer (ECS/Systems.zig): a run locks what its system lists in the ECS it starts from and in the connected
//! ECSs its In entries name, for as long as it runs, and hands back what Run returns. The debug checks report, once, a
//! run that uses something it didn't list or an ECS it wasn't given. Run with `zig build test-engine`.
const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig");
const ECS = @import("../../ECS/ECSManager.zig");
const Systems = @import("../../ECS/Systems.zig");
const In = Systems.In;

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

    fn Connect(self: *TestLayer, a: anytype, b: anytype) !void {
        try self.mSystems.Connect(self.mEngineContext.EngineAllocator(), a, b);
    }

    fn NewBody(self: *TestLayer) !u32 {
        return try self.mBodies.CreateEntity(self.mEngineContext.EngineAllocator());
    }
};

fn IsLocked(ecs: anytype, comptime component_type: type) bool {
    return ecs.mLockCounts[@TypeOf(ecs.*).ComponentInd(component_type)] > 0;
}

/// What the systems below saw while they ran, for the tests to check afterwards
const Seen = struct {
    mPositionLocked: bool = false,
    mVelocityLocked: bool = false,
    mHealthLocked: bool = true,
    mGravityLocked: bool = false,
    mOtherGravityLocked: bool = false,
    mWeatherLocked: bool = true,
    mBodiesAllowHealth: bool = true,
    mBodiesAllowPosition: bool = false,
    mSceneAllowsGravity: bool = false,
    mSceneAllowsWeather: bool = true,
    mRunName: []const u8 = "",
    mPositionsDuring: usize = 0,
    mStagedVisible: bool = false,
    mPositionsAfterInner: usize = 0,
    mAllowsHealthUnchecked: bool = false,
    mSceneAllowsWeatherUnchecked: bool = false,
    mAllowsHealthAfterUnchecked: bool = true,
};

//----------------what gets locked----------------

const BodiesInScenes = struct {
    pub const Name = "BodiesInScenes";
    pub const Reads = &.{ Position, In(SceneECS, Gravity) };
    pub const Writes = &.{Velocity};

    pub fn Run(_: *EngineContext, layer: *TestLayer, seen: *Seen) void {
        seen.mPositionLocked = IsLocked(&layer.mBodies, Position);
        seen.mVelocityLocked = IsLocked(&layer.mBodies, Velocity);
        seen.mHealthLocked = IsLocked(&layer.mBodies, Health);
        seen.mGravityLocked = IsLocked(&layer.mScene, Gravity);
        seen.mOtherGravityLocked = IsLocked(&layer.mOtherScene, Gravity);
        seen.mWeatherLocked = IsLocked(&layer.mScene, Weather);
        seen.mBodiesAllowHealth = layer.mBodies.AllowsAccess(Health);
        seen.mBodiesAllowPosition = layer.mBodies.AllowsAccess(Position);
        seen.mSceneAllowsGravity = layer.mScene.AllowsAccess(Gravity);
        seen.mSceneAllowsWeather = layer.mScene.AllowsAccess(Weather);
        seen.mRunName = layer.mSystems.mCurrentRun.?.mName;
    }
};

test "a run locks plain types where it starts and In types in the connected ECS" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    try layer.Connect(&layer.mBodies, &layer.mScene);
    var seen: Seen = .{};

    try layer.mSystems.RunSystem(BodiesInScenes, layer.mEngineContext, &layer.mBodies, .{ layer, &seen });

    //what it listed, where it listed it, and nothing else
    try std.testing.expect(seen.mPositionLocked);
    try std.testing.expect(seen.mVelocityLocked);
    try std.testing.expect(!seen.mHealthLocked);
    try std.testing.expect(seen.mGravityLocked);
    try std.testing.expect(!seen.mWeatherLocked);
    //a scene ECS it isn't connected to is left alone
    try std.testing.expect(!seen.mOtherGravityLocked);
    //each ECS it reached holds its record
    try std.testing.expect(seen.mBodiesAllowPosition);
    try std.testing.expect(!seen.mBodiesAllowHealth);
    try std.testing.expect(seen.mSceneAllowsGravity);
    try std.testing.expect(!seen.mSceneAllowsWeather);
    try std.testing.expectEqualStrings("BodiesInScenes", seen.mRunName);

    //all let go of once it is done
    try std.testing.expectEqual(@as(u32, 0), layer.mBodies.mLockTotal);
    try std.testing.expectEqual(@as(u32, 0), layer.mScene.mLockTotal);
    try std.testing.expect(layer.mBodies.mCurrentSystem == null);
    try std.testing.expect(layer.mScene.mCurrentSystem == null);
    try std.testing.expect(layer.mSystems.mCurrentRun == null);
}

test "In reaches every connected ECS of its kind" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    try layer.Connect(&layer.mBodies, &layer.mScene);
    try layer.Connect(&layer.mOtherScene, &layer.mBodies);
    var seen: Seen = .{};

    try layer.mSystems.RunSystem(BodiesInScenes, layer.mEngineContext, &layer.mBodies, .{ layer, &seen });

    try std.testing.expect(seen.mGravityLocked);
    try std.testing.expect(seen.mOtherGravityLocked);
    try std.testing.expectEqual(@as(u32, 0), layer.mOtherScene.mLockTotal);
}

test "a run whose In kind has nothing connected doesn't run" {
    //the warning naming the kind is expected; kept off the build runner's output (see TmplTests)
    std.testing.log_level = .err;
    defer std.testing.log_level = .warn;
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    //connected to another body ECS, but to no scene ECS
    try layer.Connect(&layer.mBodies, &layer.mOtherBodies);
    var seen: Seen = .{};

    try std.testing.expectError(error.NoConnectedECS, layer.mSystems.RunSystem(BodiesInScenes, layer.mEngineContext, &layer.mBodies, .{ layer, &seen }));

    try std.testing.expectEqualStrings("", seen.mRunName);
    try std.testing.expectEqual(@as(u32, 0), layer.mBodies.mLockTotal);
}

test "Disconnect and Unregister take the connection away" {
    std.testing.log_level = .err;
    defer std.testing.log_level = .warn;
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    var seen: Seen = .{};

    try layer.Connect(&layer.mBodies, &layer.mScene);
    //connecting twice, either way round, is still one connection
    try layer.Connect(&layer.mScene, &layer.mBodies);
    try std.testing.expectEqual(@as(usize, 1), layer.mSystems.mEdges.items.len);

    layer.mSystems.Disconnect(&layer.mScene, &layer.mBodies);
    try std.testing.expectError(error.NoConnectedECS, layer.mSystems.RunSystem(BodiesInScenes, layer.mEngineContext, &layer.mBodies, .{ layer, &seen }));

    try layer.Connect(&layer.mBodies, &layer.mScene);
    layer.mSystems.Unregister(layer.mEngineContext.EngineAllocator(), &layer.mScene);
    try std.testing.expectEqual(@as(usize, 0), layer.mSystems.mEdges.items.len);
    try std.testing.expectError(error.NoConnectedECS, layer.mSystems.RunSystem(BodiesInScenes, layer.mEngineContext, &layer.mBodies, .{ layer, &seen }));
    //and it can't be connected until it is registered again
    try std.testing.expectError(error.ECSNotRegistered, layer.Connect(&layer.mBodies, &layer.mScene));
}

const OnlyPlain = struct {
    pub const Name = "OnlyPlain";
    pub const Reads = &.{Health};
    pub const Writes = &.{};

    pub fn Run(_: *EngineContext, bodies: *BodyECS) bool {
        return IsLocked(bodies, Health);
    }
};

test "a system with only plain types runs on an ECS the layer doesn't know" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    layer.mSystems.Unregister(layer.mEngineContext.EngineAllocator(), &layer.mBodies);

    try std.testing.expect(try layer.mSystems.RunSystem(OnlyPlain, layer.mEngineContext, &layer.mBodies, .{&layer.mBodies}));
}

//----------------what lands, and what comes back----------------

const AddsPositions = struct {
    pub const Name = "AddsPositions";
    pub const Reads = &.{};
    pub const Writes = &.{Position};

    pub fn Run(engine_context: *EngineContext, bodies: *BodyECS, seen: *Seen) !void {
        const entity_id = try bodies.CreateEntity(engine_context.EngineAllocator());
        _ = try bodies.AddComponent(engine_context, entity_id, Position{ .x = 3 });
        seen.mStagedVisible = bodies.HasComponent(Position, entity_id);
        seen.mPositionsDuring = bodies.NumWithComponent(Position);
    }
};

test "what a run adds of what it locked lands once it is done" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    var seen: Seen = .{};

    try layer.mSystems.RunSystem(AddsPositions, layer.mEngineContext, &layer.mBodies, .{ &layer.mBodies, &seen });

    try std.testing.expect(seen.mStagedVisible);
    try std.testing.expectEqual(@as(usize, 0), seen.mPositionsDuring);
    try std.testing.expectEqual(@as(usize, 1), layer.mBodies.NumWithComponent(Position));
}

const Counts = struct {
    pub const Name = "Counts";
    pub const Reads = &.{Position};
    pub const Writes = &.{};

    pub fn Run(_: *EngineContext, bodies: *BodyECS, extra: u32) u32 {
        return @as(u32, @intCast(bodies.NumWithComponent(Position))) + extra;
    }
};

const FailsAfterAdding = struct {
    pub const Name = "FailsAfterAdding";
    pub const Reads = &.{};
    pub const Writes = &.{Position};

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

    try std.testing.expectEqual(@as(u32, 11), try layer.mSystems.RunSystem(Counts, layer.mEngineContext, &layer.mBodies, .{ &layer.mBodies, 10 }));

    try std.testing.expectError(error.SystemFailed, layer.mSystems.RunSystem(FailsAfterAdding, layer.mEngineContext, &layer.mBodies, .{&layer.mBodies}));
    //nothing left locked, and what it added before failing still landed
    try std.testing.expectEqual(@as(u32, 0), layer.mBodies.mLockTotal);
    try std.testing.expect(layer.mBodies.mCurrentSystem == null);
    try std.testing.expectEqual(@as(usize, 2), layer.mBodies.NumWithComponent(Position));
}

const HoldsPositions = struct {
    pub const Name = "HoldsPositions";
    pub const Reads = &.{Position};
    pub const Writes = &.{};

    pub fn Run(engine_context: *EngineContext, layer: *TestLayer, seen: *Seen) !void {
        try layer.mSystems.RunSystem(AddsPositions, engine_context, &layer.mBodies, .{ &layer.mBodies, seen });
        seen.mPositionsAfterInner = layer.mBodies.NumWithComponent(Position);
        seen.mRunName = layer.mSystems.mCurrentRun.?.mName;
    }
};

test "a run inside another leaves the landing to the outer one" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    var seen: Seen = .{};

    try layer.mSystems.RunSystem(HoldsPositions, layer.mEngineContext, &layer.mBodies, .{ layer, &seen });

    try std.testing.expectEqual(@as(usize, 0), seen.mPositionsAfterInner);
    //back to the outer run once the inner one was done
    try std.testing.expectEqualStrings("HoldsPositions", seen.mRunName);
    try std.testing.expectEqual(@as(usize, 1), layer.mBodies.NumWithComponent(Position));
    try std.testing.expect(layer.mSystems.mCurrentRun == null);
}

//----------------unchecked bookkeeping----------------

const DoesBookkeeping = struct {
    pub const Name = "DoesBookkeeping";
    pub const Reads = &.{ Position, In(SceneECS, Gravity) };
    pub const Writes = &.{};

    pub fn Run(_: *EngineContext, layer: *TestLayer, seen: *Seen) void {
        var unchecked: Systems.UncheckedScope(BodyECS, &.{SceneECS}) = undefined;
        unchecked.Enter(&layer.mSystems, &layer.mBodies);
        seen.mAllowsHealthUnchecked = layer.mBodies.AllowsAccess(Health);
        seen.mSceneAllowsWeatherUnchecked = layer.mScene.AllowsAccess(Weather);
        unchecked.Leave();
        seen.mAllowsHealthAfterUnchecked = layer.mBodies.AllowsAccess(Health);
    }
};

test "an unchecked scope lets engine bookkeeping inside a run touch anything" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    try layer.Connect(&layer.mBodies, &layer.mScene);
    var seen: Seen = .{};

    try layer.mSystems.RunSystem(DoesBookkeeping, layer.mEngineContext, &layer.mBodies, .{ layer, &seen });

    try std.testing.expect(seen.mAllowsHealthUnchecked);
    try std.testing.expect(seen.mSceneAllowsWeatherUnchecked);
    //and the system's own record is back once it is left
    try std.testing.expect(!seen.mAllowsHealthAfterUnchecked);
    //it locked nothing of its own
    try std.testing.expectEqual(@as(u32, 0), layer.mBodies.mLockTotal);
    try std.testing.expectEqual(@as(u32, 0), layer.mScene.mLockTotal);
}

//----------------the debug checks----------------

/// For a test that makes a mistake on purpose: the checks report it as a warning, kept off the build runner's output.
/// Hands back how many mistakes had been reported before, which the test counts from
fn ExpectReports() usize {
    ECS.access_report_level = .warn;
    std.testing.log_level = .err;
    return ECS.ReportedCount();
}

fn StopExpectingReports() void {
    ECS.access_report_level = .err;
    std.testing.log_level = .warn;
}

const UsesUnlisted = struct {
    pub const Name = "UsesUnlisted";
    pub const Reads = &.{Position};
    pub const Writes = &.{};

    pub fn Run(_: *EngineContext, bodies: *BodyECS, body: u32) void {
        //the same mistake on every pass of a loop
        for (0..10) |_| _ = bodies.GetComponent(Health, body);
        _ = bodies.GetComponent(Position, body);
    }
};

test "a component used without being listed is reported once" {
    if (!std.debug.runtime_safety) return error.SkipZigTest;
    const before = ExpectReports();
    defer StopExpectingReports();
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const body = try layer.NewBody();
    _ = try layer.mBodies.AddComponent(layer.mEngineContext, body, Health{});

    try layer.mSystems.RunSystem(UsesUnlisted, layer.mEngineContext, &layer.mBodies, .{ &layer.mBodies, body });
    try std.testing.expectEqual(before + 1, ECS.ReportedCount());

    //and not again on the next run
    try layer.mSystems.RunSystem(UsesUnlisted, layer.mEngineContext, &layer.mBodies, .{ &layer.mBodies, body });
    try std.testing.expectEqual(before + 1, ECS.ReportedCount());
}

const QueriesUnlisted = struct {
    pub const Name = "QueriesUnlisted";
    pub const Reads = &.{Position};
    pub const Writes = &.{};

    pub fn Run(_: *EngineContext, bodies: *BodyECS) !void {
        const allocator = std.testing.allocator;
        //listed, and a tag: neither is a mistake
        var listed = try bodies.GetGroup(allocator, .{ .And = &.{ .{ .Component = Position }, .{ .Component = ECS.EntityTagComponent } } });
        listed.deinit(allocator);
        //Health inside the query is
        var unlisted = try bodies.GetGroup(allocator, .{ .Or = &.{ .{ .Component = Position }, .{ .Component = Health } } });
        unlisted.deinit(allocator);
    }
};

test "a query counts as using every component in it" {
    if (!std.debug.runtime_safety) return error.SkipZigTest;
    const before = ExpectReports();
    defer StopExpectingReports();
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;

    try layer.mSystems.RunSystem(QueriesUnlisted, layer.mEngineContext, &layer.mBodies, .{&layer.mBodies});
    try std.testing.expectEqual(before + 1, ECS.ReportedCount());
}

const TouchesScene = struct {
    pub const Name = "TouchesScene";
    pub const Reads = &.{Position};
    pub const Writes = &.{};

    pub fn Run(_: *EngineContext, layer: *TestLayer, scene: u32) void {
        _ = layer.mScene.GetComponent(Gravity, scene);
    }
};

const GivenScene = struct {
    pub const Name = "GivenScene";
    pub const Reads = &.{ Position, In(SceneECS, Gravity) };
    pub const Writes = &.{};

    pub fn Run(engine_context: *EngineContext, layer: *TestLayer, scene: u32) !void {
        //given it, so fine
        _ = layer.mScene.GetComponent(Gravity, scene);
        //a run inside it that wasn't given the scene ECS can't lean on this one having been
        try layer.mSystems.RunSystem(TouchesScene, engine_context, &layer.mBodies, .{ layer, scene });
    }
};

test "an ECS used by a run that wasn't given it is reported" {
    if (!std.debug.runtime_safety) return error.SkipZigTest;
    const before = ExpectReports();
    defer StopExpectingReports();
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    try layer.Connect(&layer.mBodies, &layer.mScene);
    const scene = try layer.mScene.CreateEntity(layer.mEngineContext.EngineAllocator());
    _ = try layer.mScene.AddComponent(layer.mEngineContext, scene, Gravity{});

    //connected, but not listed through an In: not given
    try layer.mSystems.RunSystem(TouchesScene, layer.mEngineContext, &layer.mBodies, .{ layer, scene });
    try std.testing.expectEqual(before + 1, ECS.ReportedCount());

    //given, with that same mistake inside it: nothing new
    try layer.mSystems.RunSystem(GivenScene, layer.mEngineContext, &layer.mBodies, .{ layer, scene });
    try std.testing.expectEqual(before + 1, ECS.ReportedCount());

    //outside any run, anything goes
    _ = layer.mScene.GetComponent(Gravity, scene);
    try std.testing.expectEqual(before + 1, ECS.ReportedCount());
}

const BookkeepsInScene = struct {
    pub const Name = "BookkeepsInScene";
    pub const Reads = &.{Position};
    pub const Writes = &.{};

    pub fn Run(_: *EngineContext, layer: *TestLayer, scene: u32) void {
        var unchecked: Systems.UncheckedScope(BodyECS, &.{SceneECS}) = undefined;
        unchecked.Enter(&layer.mSystems, &layer.mBodies);
        defer unchecked.Leave();
        _ = layer.mScene.GetComponent(Weather, scene);
        _ = layer.mBodies.GetComponent(Health, 0);
    }
};

test "engine bookkeeping in an unchecked scope isn't reported" {
    if (!std.debug.runtime_safety) return error.SkipZigTest;
    const before = ExpectReports();
    defer StopExpectingReports();
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    try layer.Connect(&layer.mBodies, &layer.mScene);
    _ = try layer.NewBody();
    const scene = try layer.mScene.CreateEntity(layer.mEngineContext.EngineAllocator());

    try layer.mSystems.RunSystem(BookkeepsInScene, layer.mEngineContext, &layer.mBodies, .{ layer, scene });
    try std.testing.expectEqual(before, ECS.ReportedCount());
}

const ChangesWhatItReads = struct {
    pub const Name = "ChangesWhatItReads";
    pub const Reads = &.{ Position, In(SceneECS, Gravity) };
    pub const Writes = &.{ Velocity, In(SceneECS, Weather) };

    pub fn Run(_: *EngineContext, layer: *TestLayer, body: u32, scene: u32) void {
        //listed in Writes, or only read: fine
        _ = layer.mBodies.GetComponentMut(Velocity, body);
        _ = layer.mBodies.GetComponent(Position, body);
        _ = layer.mScene.GetComponentMut(Weather, scene);
        _ = layer.mScene.GetComponent(Gravity, scene);
        //only in Reads, so a mistake, here and through In
        _ = layer.mBodies.GetComponentMut(Position, body);
        _ = layer.mBodies.GetComponentSliceMut(Position);
        _ = layer.mScene.GetComponentMut(Gravity, scene);
    }
};

test "changing a component only listed in Reads is reported" {
    if (!std.debug.runtime_safety) return error.SkipZigTest;
    const before = ExpectReports();
    defer StopExpectingReports();
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    try layer.Connect(&layer.mBodies, &layer.mScene);
    const body = try layer.NewBody();
    const scene = try layer.mScene.CreateEntity(layer.mEngineContext.EngineAllocator());

    try layer.mSystems.RunSystem(ChangesWhatItReads, layer.mEngineContext, &layer.mBodies, .{ layer, body, scene });
    //Position once (one entity or all of them, it's the same mistake) and Gravity once
    try std.testing.expectEqual(before + 2, ECS.ReportedCount());
}

const ReadsPositionOnly = struct {
    pub const Name = "ReadsPositionOnly";
    pub const Reads = &.{Position};
    pub const Writes = &.{};

    pub fn Run(_: *EngineContext, bodies: *BodyECS, allows: *[3]bool) void {
        allows[0] = bodies.AllowsAccess(BodyECS.ParentComponent) and bodies.AllowsAccess(BodyECS.ChildComponent);
        allows[1] = bodies.AllowsAccess(ECS.MainObjectComponent) and bodies.AllowsWrite(ECS.MainObjectComponent);
        allows[2] = bodies.AllowsAccess(Health);
    }
};

test "the hierarchy and tags are always allowed in a run, what it didn't list isn't" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    var allows: [3]bool = .{ false, false, true };

    try layer.mSystems.RunSystem(ReadsPositionOnly, layer.mEngineContext, &layer.mBodies, .{ &layer.mBodies, &allows });

    try std.testing.expect(allows[0]);
    try std.testing.expect(allows[1]);
    try std.testing.expect(!allows[2]);
    //and everything again once it is done
    try std.testing.expect(layer.mBodies.AllowsAccess(Health));
}

test "a change can only go straight to storage that isn't locked" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const bodies = &layer.mBodies;

    bodies.Lock(&.{ Position, ECS.MainObjectComponent });
    try std.testing.expect(!bodies.CanChangeStorage(Position.Ind));
    try std.testing.expect(bodies.CanChangeStorage(Health.Ind));
    //a tag has no storage to move, locked or not
    try std.testing.expect(bodies.CanChangeStorage(ECS.MainObjectComponent.Ind));
    try bodies.Unlock(layer.mEngineContext, &.{ Position, ECS.MainObjectComponent });
    try std.testing.expect(bodies.CanChangeStorage(Position.Ind));
}
