//! Transactions in the systems layer (ECS/Transaction.zig, Systems.RunTransaction): what code changes in a component
//! inside one is kept apart until it returns, then put in or dropped as if it never happened. Run with
//! `zig build test-engine`.
const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig");
const ECS = @import("../../ECS/ECSManager.zig");
const Systems = @import("../../ECS/Systems.zig");

const Position = struct {
    pub const Name: []const u8 = "Position";
    pub const Ind: usize = ECS.BuiltinComponentCount;
    x: f32 = 0,
    pub fn Deinit(_: *Position, _: *EngineContext) void {}
};

/// Owns memory, so a transaction has to deep copy it, and free whichever copy loses
const Label = struct {
    pub const Name: []const u8 = "Label";
    pub const Ind: usize = ECS.BuiltinComponentCount + 1;
    mText: std.ArrayList(u8) = .empty,
    pub fn Deinit(self: *Label, engine_context: *EngineContext) void {
        self.mText.deinit(engine_context.EngineAllocator());
    }
    pub fn Clone(self: *const Label, engine_context: *EngineContext) !Label {
        return .{ .mText = try self.mText.clone(engine_context.EngineAllocator()) };
    }
};

const BodyECS = ECS.ECSManager(u32, &[_]type{ Position, Label }, "TransactionBodyECS");

/// One registered ECS, the layer, and the minimal EngineContext they need. Deinit fails the test on a leak
const TestLayer = struct {
    mEngineContext: *EngineContext,
    mSystems: Systems = .empty,
    mBodies: BodyECS = .empty,

    fn Init() !*TestLayer {
        const self = try std.heap.page_allocator.create(TestLayer);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        self.mEngineContext.* = .{};
        const engine_allocator = self.mEngineContext.EngineAllocator();
        try self.mBodies.Init(engine_allocator);
        try self.mSystems.Register(engine_allocator, &self.mBodies);
        return self;
    }

    fn Deinit(self: *TestLayer) !void {
        const engine_context = self.mEngineContext;
        self.mSystems.Unregister(engine_context.EngineAllocator(), &self.mBodies);
        self.mBodies.Deinit(engine_context);
        const leak_check = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
        try std.testing.expect(leak_check == .ok);
    }

    fn NewBody(self: *TestLayer, x: f32) !u32 {
        const engine_context = self.mEngineContext;
        const id = try self.mBodies.CreateEntity(engine_context.EngineAllocator());
        _ = try self.mBodies.AddComponent(engine_context, id, Position{ .x = x });
        return id;
    }

    fn NewLabel(self: *TestLayer, text: []const u8) !u32 {
        const engine_context = self.mEngineContext;
        const id = try self.mBodies.CreateEntity(engine_context.EngineAllocator());
        var label = Label{};
        try label.mText.appendSlice(engine_context.EngineAllocator(), text);
        _ = try self.mBodies.AddComponent(engine_context, id, label);
        return id;
    }

    fn X(self: *TestLayer, id: u32) f32 {
        return self.mBodies.mComponentManager.GetComponent(Position, id).?.x;
    }
};

/// What the code inside a transaction saw, for the tests to check afterwards
const Seen = struct {
    mOwnChange: f32 = 0,
    mStorageDuring: f32 = 0,
    mSameCopy: bool = false,
};

fn Keep(result: bool) bool {
    return result;
}

/// Moves the body to 5 and hands back `keep`
fn MovesTo5(bodies: *BodyECS, id: u32, seen: *Seen, keep: bool) bool {
    const position = bodies.GetComponentMut(Position, id).?;
    position.x = 5;
    seen.mOwnChange = bodies.GetComponent(Position, id).?.x;
    seen.mStorageDuring = bodies.mComponentManager.GetComponent(Position, id).?.x;
    seen.mSameCopy = bodies.GetComponentMut(Position, id).? == position;
    return keep;
}

test "a change made in a transaction is put in when it is kept, and the code sees it straight away" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const id = try layer.NewBody(1);
    var seen: Seen = .{};

    _ = layer.mSystems.RunTransaction(layer.mEngineContext, MovesTo5, .{ &layer.mBodies, id, &seen, true }, Keep);

    try std.testing.expectEqual(@as(f32, 5), seen.mOwnChange);
    try std.testing.expectEqual(@as(f32, 1), seen.mStorageDuring);
    try std.testing.expect(seen.mSameCopy);
    try std.testing.expectEqual(@as(f32, 5), layer.X(id));
    try std.testing.expect(layer.mSystems.mOpenTransaction == null);
}

test "a change made in a transaction that isn't kept is dropped" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const id = try layer.NewBody(1);
    var seen: Seen = .{};

    _ = layer.mSystems.RunTransaction(layer.mEngineContext, MovesTo5, .{ &layer.mBodies, id, &seen, false }, Keep);

    try std.testing.expectEqual(@as(f32, 5), seen.mOwnChange);
    try std.testing.expectEqual(@as(f32, 1), layer.X(id));
}

test "outside a transaction a change goes straight to storage" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const id = try layer.NewBody(1);
    var seen: Seen = .{};

    _ = MovesTo5(&layer.mBodies, id, &seen, false);

    try std.testing.expectEqual(@as(f32, 5), seen.mStorageDuring);
    try std.testing.expectEqual(@as(f32, 5), layer.X(id));
}

/// Adds to a label, and hands back `keep`
fn Appends(bodies: *BodyECS, engine_context: *EngineContext, id: u32, keep: bool) bool {
    const label = bodies.GetComponentMut(Label, id).?;
    label.mText.appendSlice(engine_context.EngineAllocator(), " and more, enough to grow the list") catch unreachable;
    return keep;
}

test "a component that owns memory is deep copied: kept or dropped, nothing leaks and the other copy is untouched" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const engine_context = layer.mEngineContext;
    const kept = try layer.NewLabel("kept");
    const dropped = try layer.NewLabel("dropped");

    _ = layer.mSystems.RunTransaction(engine_context, Appends, .{ &layer.mBodies, engine_context, kept, true }, Keep);
    _ = layer.mSystems.RunTransaction(engine_context, Appends, .{ &layer.mBodies, engine_context, dropped, false }, Keep);

    try std.testing.expectEqualStrings("kept and more, enough to grow the list", layer.mBodies.GetComponent(Label, kept).?.mText.items);
    try std.testing.expectEqualStrings("dropped", layer.mBodies.GetComponent(Label, dropped).?.mText.items);
}

/// Changes the label, then takes it off the entity before the transaction ends (outside a run, so right away)
fn AppendsThenRemoves(bodies: *BodyECS, engine_context: *EngineContext, id: u32) bool {
    _ = Appends(bodies, engine_context, id, true);
    bodies.RemoveComponent(engine_context, id, Label.Ind) catch unreachable;
    return true;
}

test "a copy of a component gone by the time it is kept is freed, not put back" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const engine_context = layer.mEngineContext;
    const id = try layer.NewLabel("going");

    _ = layer.mSystems.RunTransaction(engine_context, AppendsThenRemoves, .{ &layer.mBodies, engine_context, id }, Keep);

    try std.testing.expect(!layer.mBodies.HasComponent(Label, id));
}

/// Moves the body to 5 inside a transaction of its own that says not to keep it, then hands back `keep`
fn MovesInsideAnother(systems: *Systems, engine_context: *EngineContext, bodies: *BodyECS, id: u32, keep: bool) bool {
    var seen: Seen = .{};
    _ = systems.RunTransaction(engine_context, MovesTo5, .{ bodies, id, &seen, false }, Keep);
    return keep;
}

test "a transaction inside another is part of it, and goes or stays with it" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const engine_context = layer.mEngineContext;
    const kept = try layer.NewBody(1);
    const dropped = try layer.NewBody(1);

    _ = layer.mSystems.RunTransaction(engine_context, MovesInsideAnother, .{ &layer.mSystems, engine_context, &layer.mBodies, kept, true }, Keep);
    _ = layer.mSystems.RunTransaction(engine_context, MovesInsideAnother, .{ &layer.mSystems, engine_context, &layer.mBodies, dropped, false }, Keep);

    try std.testing.expectEqual(@as(f32, 5), layer.X(kept));
    try std.testing.expectEqual(@as(f32, 1), layer.X(dropped));
}

/// Changes several bodies, and hands back `keep`
fn MovesAll(bodies: *BodyECS, ids: []const u32, keep: bool) bool {
    for (ids, 0..) |id, ind| bodies.GetComponentMut(Position, id).?.x = @floatFromInt(10 + ind);
    return keep;
}

test "a transaction that is used again starts empty" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const engine_context = layer.mEngineContext;
    const ids = [_]u32{ try layer.NewBody(1), try layer.NewBody(1), try layer.NewBody(1) };

    _ = layer.mSystems.RunTransaction(engine_context, MovesAll, .{ &layer.mBodies, ids[0..], false }, Keep);
    _ = layer.mSystems.RunTransaction(engine_context, MovesAll, .{ &layer.mBodies, ids[0..1], true }, Keep);

    try std.testing.expectEqual(@as(f32, 10), layer.X(ids[0]));
    try std.testing.expectEqual(@as(f32, 1), layer.X(ids[1]));
    try std.testing.expectEqual(@as(f32, 1), layer.X(ids[2]));
}
