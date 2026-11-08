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

/// A tag: put on and taken off right away, even in a run
const Frozen = struct {
    pub const Name: []const u8 = "Frozen";
    pub const Ind: usize = ECS.BuiltinComponentCount + 2;
    pub fn Deinit(_: *Frozen, _: *EngineContext) void {}
};

const BodyECS = ECS.ECSManager(u32, &[_]type{ Position, Label, Frozen }, "TransactionBodyECS");

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

/// Changes the label, then takes it off the entity. A transaction is a run, so the removal waits for it to end
fn AppendsThenRemoves(bodies: *BodyECS, engine_context: *EngineContext, id: u32) bool {
    _ = Appends(bodies, engine_context, id, true);
    bodies.RemoveComponent(engine_context, id, Label.Ind) catch unreachable;
    return true;
}

test "a component changed then removed in a kept transaction is put in, then removed when the transaction lands" {
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

//----------------structural changes----------------

/// Makes a body with a position, a label and a child, and hands back `keep`
fn MakesBody(bodies: *BodyECS, engine_context: *EngineContext, made: *u32, child: *u32, keep: bool) bool {
    made.* = bodies.CreateEntity(engine_context.EngineAllocator()) catch unreachable;
    _ = bodies.AddComponent(engine_context, made.*, Position{ .x = 2 }) catch unreachable;
    var label = Label{};
    label.mText.appendSlice(engine_context.EngineAllocator(), "new") catch unreachable;
    _ = bodies.AddComponent(engine_context, made.*, label) catch unreachable;
    child.* = bodies.AddChild(engine_context, made.*, .Entity) catch unreachable;
    _ = bodies.AddComponent(engine_context, child.*, Position{ .x = 3 }) catch unreachable;
    return keep;
}

test "an object made in a kept transaction lands with what was added to it" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const engine_context = layer.mEngineContext;
    var made: u32 = undefined;
    var child: u32 = undefined;

    _ = layer.mSystems.RunTransaction(engine_context, MakesBody, .{ &layer.mBodies, engine_context, &made, &child, true }, Keep);

    try std.testing.expect(layer.mBodies.IsActiveEntity(made));
    try std.testing.expect(layer.mBodies.IsActiveEntity(child));
    try std.testing.expectEqual(@as(f32, 2), layer.X(made));
    try std.testing.expectEqualStrings("new", layer.mBodies.GetComponent(Label, made).?.mText.items);
    try std.testing.expectEqual(@as(usize, 2), layer.mBodies.mComponentManager.NumWithComponent(Position));
}

test "an object made in a dropped transaction is destroyed, children and staged components too, and nothing leaks" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const engine_context = layer.mEngineContext;
    const existing = try layer.NewBody(1);
    var made: u32 = undefined;
    var child: u32 = undefined;

    _ = layer.mSystems.RunTransaction(engine_context, MakesBody, .{ &layer.mBodies, engine_context, &made, &child, false }, Keep);

    try std.testing.expect(!layer.mBodies.IsActiveEntity(made));
    try std.testing.expect(!layer.mBodies.IsActiveEntity(child));
    try std.testing.expect(layer.mBodies.IsActiveEntity(existing));
    try std.testing.expectEqual(@as(usize, 1), layer.mBodies.NumWithComponent(Position));
    try std.testing.expectEqual(@as(usize, 0), layer.mBodies.NumWithComponent(Label));
}

/// What ChangesExisting does to three bodies that were there before
const Existing = struct {
    mAddTo: u32,
    mRemoveFrom: u32,
    mDestroy: u32,
};

/// Adds a label to one body, takes the position off another, destroys a third, and hands back `keep`
fn ChangesExisting(bodies: *BodyECS, engine_context: *EngineContext, existing: Existing, keep: bool) bool {
    var label = Label{};
    label.mText.appendSlice(engine_context.EngineAllocator(), "added") catch unreachable;
    _ = bodies.AddComponent(engine_context, existing.mAddTo, label) catch unreachable;
    bodies.RemoveComponent(engine_context, existing.mRemoveFrom, Position.Ind) catch unreachable;
    bodies.DestroyEntity(engine_context, existing.mDestroy) catch unreachable;
    return keep;
}

test "adds, removals and destroys on objects that were there before land when kept, and never happen when dropped" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const engine_context = layer.mEngineContext;
    const kept = Existing{ .mAddTo = try layer.NewBody(1), .mRemoveFrom = try layer.NewBody(1), .mDestroy = try layer.NewBody(1) };
    const dropped = Existing{ .mAddTo = try layer.NewBody(1), .mRemoveFrom = try layer.NewBody(1), .mDestroy = try layer.NewBody(1) };

    _ = layer.mSystems.RunTransaction(engine_context, ChangesExisting, .{ &layer.mBodies, engine_context, kept, true }, Keep);
    _ = layer.mSystems.RunTransaction(engine_context, ChangesExisting, .{ &layer.mBodies, engine_context, dropped, false }, Keep);

    try std.testing.expectEqualStrings("added", layer.mBodies.GetComponent(Label, kept.mAddTo).?.mText.items);
    try std.testing.expect(!layer.mBodies.HasComponent(Position, kept.mRemoveFrom));
    try std.testing.expect(!layer.mBodies.IsActiveEntity(kept.mDestroy));

    try std.testing.expect(!layer.mBodies.HasComponent(Label, dropped.mAddTo));
    try std.testing.expect(layer.mBodies.HasComponent(Position, dropped.mRemoveFrom));
    try std.testing.expect(layer.mBodies.IsActiveEntity(dropped.mDestroy));
}

/// Takes the tag off one body, puts it on another, puts it on and takes it off a third, and hands back `keep`
fn MovesTags(bodies: *BodyECS, engine_context: *EngineContext, frozen: u32, thawed: u32, flicker: u32, keep: bool) bool {
    bodies.RemoveComponent(engine_context, frozen, Frozen.Ind) catch unreachable;
    _ = bodies.AddComponent(engine_context, thawed, Frozen{}) catch unreachable;
    _ = bodies.AddComponent(engine_context, flicker, Frozen{}) catch unreachable;
    bodies.RemoveComponent(engine_context, flicker, Frozen.Ind) catch unreachable;
    return keep;
}

test "tags put on or taken off in a dropped transaction are put back as they were" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const engine_context = layer.mEngineContext;
    const frozen = try layer.NewBody(1);
    _ = try layer.mBodies.AddComponent(engine_context, frozen, Frozen{});
    const thawed = try layer.NewBody(1);
    const flicker = try layer.NewBody(1);

    _ = layer.mSystems.RunTransaction(engine_context, MovesTags, .{ &layer.mBodies, engine_context, frozen, thawed, flicker, false }, Keep);

    try std.testing.expect(layer.mBodies.HasComponent(Frozen, frozen));
    try std.testing.expect(!layer.mBodies.HasComponent(Frozen, thawed));
    try std.testing.expect(!layer.mBodies.HasComponent(Frozen, flicker));

    _ = layer.mSystems.RunTransaction(engine_context, MovesTags, .{ &layer.mBodies, engine_context, frozen, thawed, flicker, true }, Keep);

    try std.testing.expect(!layer.mBodies.HasComponent(Frozen, frozen));
    try std.testing.expect(layer.mBodies.HasComponent(Frozen, thawed));
    try std.testing.expect(!layer.mBodies.HasComponent(Frozen, flicker));
}

/// Gives the parent a new child, and hands back `keep`
fn AddsChild(bodies: *BodyECS, engine_context: *EngineContext, parent: u32, keep: bool) bool {
    _ = bodies.AddChild(engine_context, parent, .Entity) catch unreachable;
    return keep;
}

test "a child made in a dropped transaction leaves its parent's list as it was" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const engine_context = layer.mEngineContext;
    const childless = try layer.NewBody(1);
    const parent = try layer.NewBody(1);
    const first_child = try layer.mBodies.AddChild(engine_context, parent, .Entity);

    _ = layer.mSystems.RunTransaction(engine_context, AddsChild, .{ &layer.mBodies, engine_context, childless, false }, Keep);
    _ = layer.mSystems.RunTransaction(engine_context, AddsChild, .{ &layer.mBodies, engine_context, parent, false }, Keep);

    try std.testing.expect(!layer.mBodies.HasComponent(BodyECS.ParentComponent, childless));
    const only = layer.mBodies.GetComponent(BodyECS.ChildComponent, first_child).?;
    try std.testing.expectEqual(first_child, only.mNext);
    try std.testing.expectEqual(first_child, only.mPrev);
    try std.testing.expectEqual(first_child, layer.mBodies.GetComponent(BodyECS.ParentComponent, parent).?.mFirstEntity);
}

/// Destroys a body, and says not to keep it
fn DestroysAndDrops(bodies: *BodyECS, engine_context: *EngineContext, id: u32) bool {
    bodies.DestroyEntity(engine_context, id) catch unreachable;
    return false;
}

/// Destroys one body in the run, then another in a transaction inside the run that is dropped
const QueuesThenDrops = struct {
    pub const Name = "QueuesThenDrops";

    pub fn Run(engine_context: *EngineContext, systems: *Systems, bodies: *BodyECS, before: u32, inside: u32) !void {
        try bodies.DestroyEntity(engine_context, before);
        _ = systems.RunTransaction(engine_context, DestroysAndDrops, .{ bodies, engine_context, inside }, Keep);
    }
};

test "a transaction dropped inside a run only drops its own changes, not what the run queued before it" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const engine_context = layer.mEngineContext;
    const before = try layer.NewBody(1);
    const inside = try layer.NewBody(1);

    try layer.mSystems.RunSystem(QueuesThenDrops, engine_context, .{ &layer.mSystems, &layer.mBodies, before, inside });

    try std.testing.expect(!layer.mBodies.IsActiveEntity(before));
    try std.testing.expect(layer.mBodies.IsActiveEntity(inside));
    try std.testing.expectEqual(@as(u32, 0), layer.mSystems.mRunDepth);
}

//----------------actions and what can't be taken back----------------

/// Writes down which actions ran, in order
const Ran = struct {
    mOrder: [4]u8 = undefined,
    mCount: usize = 0,

    const Note = struct {
        mRan: *Ran,
        mMark: u8,

        fn Run(_: *EngineContext, self: *Note) void {
            self.mRan.mOrder[self.mRan.mCount] = self.mMark;
            self.mRan.mCount += 1;
        }
    };
};

/// Asks for two actions on commit and two on discard, and hands back `keep`
fn AsksForActions(systems: *Systems, ran: *Ran, keep: bool) bool {
    const transaction = systems.OpenTransaction().?;
    transaction.OnCommit(Ran.Note{ .mRan = ran, .mMark = 'a' }, Ran.Note.Run) catch unreachable;
    transaction.OnDiscard(Ran.Note{ .mRan = ran, .mMark = '1' }, Ran.Note.Run) catch unreachable;
    transaction.OnCommit(Ran.Note{ .mRan = ran, .mMark = 'b' }, Ran.Note.Run) catch unreachable;
    transaction.OnDiscard(Ran.Note{ .mRan = ran, .mMark = '2' }, Ran.Note.Run) catch unreachable;
    return keep;
}

test "a kept transaction runs its on-commit actions in order, a dropped one its on-discard actions newest first" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const engine_context = layer.mEngineContext;

    var kept: Ran = .{};
    _ = layer.mSystems.RunTransaction(engine_context, AsksForActions, .{ &layer.mSystems, &kept, true }, Keep);
    try std.testing.expectEqualStrings("ab", kept.mOrder[0..kept.mCount]);

    var dropped: Ran = .{};
    _ = layer.mSystems.RunTransaction(engine_context, AsksForActions, .{ &layer.mSystems, &dropped, false }, Keep);
    try std.testing.expectEqualStrings("21", dropped.mOrder[0..dropped.mCount]);
}
