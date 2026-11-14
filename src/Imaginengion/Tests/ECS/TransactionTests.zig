//! The transactions layer (ECS/Transaction.zig, Transactions.RunTransaction): what code changes in a component
//! inside one is kept apart until it returns, then put in or dropped as if it never happened. Run with
//! `zig build test-engine`.
const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig");
const ECS = @import("../../ECS/ECSManager.zig");
const Systems = @import("../../ECS/Systems.zig");
const Transactions = @import("../../ECS/Transactions.zig");

const Position = struct {
    pub const Name: []const u8 = "Position";
    pub const Ind: usize = ECS.BuiltinComponentCount;
    x: f32 = 0,
    pub fn Deinit(_: *Position, _: *EngineContext, _: std.mem.Allocator) void {}
};

/// Owns memory, so a transaction has to deep copy it, and free whichever copy loses
const Label = struct {
    pub const Name: []const u8 = "Label";
    pub const Ind: usize = ECS.BuiltinComponentCount + 1;
    mText: std.ArrayList(u8) = .empty,
    pub fn Deinit(self: *Label, _: *EngineContext, keep_allocator: std.mem.Allocator) void {
        self.mText.deinit(keep_allocator);
    }
    pub fn Clone(self: *const Label, _: *EngineContext, keep_allocator: std.mem.Allocator) !Label {
        return .{ .mText = try self.mText.clone(keep_allocator) };
    }
};

/// A tag: put on and taken off right away, even in a run
const Frozen = struct {
    pub const Name: []const u8 = "Frozen";
    pub const Ind: usize = ECS.BuiltinComponentCount + 2;
    pub fn Deinit(_: *Frozen, _: *EngineContext, _: std.mem.Allocator) void {}
};

const BodyECS = ECS.ECSManager(u32, &[_]type{ Position, Label, Frozen }, "TransactionBodyECS");

/// One registered ECS, and the minimal EngineContext it needs: the systems and transactions layers are the context's
/// own, as they are in the engine. Deinit fails the test on a leak
const TestLayer = struct {
    mEngineContext: *EngineContext,
    mSystems: *Systems,
    mTransactions: *Transactions,
    mBodies: BodyECS = .empty,
    /// A job pool of the test's own, for batches that run on several threads (InitThreaded)
    mThreads: ?*std.Io.Threaded = null,

    /// Init, with batches run on a job pool of `workers` threads besides the test's own
    fn InitThreaded(workers: usize) !*TestLayer {
        const self = try Init();
        const threads = try std.heap.page_allocator.create(std.Io.Threaded);
        threads.* = std.Io.Threaded.init(std.heap.page_allocator, .{ .async_limit = .limited(workers), .concurrent_limit = .nothing });
        self.mThreads = threads;
        self.mEngineContext.mJobPool = .{ .mIo = threads.io(), .mWorkers = workers };
        self.mEngineContext._Internal.ThreadScratchArenas.mMainThread = std.Thread.getCurrentId();
        return self;
    }

    fn Init() !*TestLayer {
        const self = try std.heap.page_allocator.create(TestLayer);
        const engine_context = try std.heap.page_allocator.create(EngineContext);
        engine_context.* = .{};
        self.* = .{ .mEngineContext = engine_context, .mSystems = &engine_context.mSystems, .mTransactions = &engine_context.mTransactions };
        const keep_allocator = engine_context.Keep();
        try self.mBodies.Init(keep_allocator);
        try self.mSystems.Register(keep_allocator, &self.mBodies);
        self.mTransactions.Register(&self.mBodies);
        return self;
    }

    fn Deinit(self: *TestLayer) !void {
        const engine_context = self.mEngineContext;
        if (self.mThreads) |threads| {
            self.mEngineContext.mJobPool = .{};
            threads.deinit();
            std.heap.page_allocator.destroy(threads);
            self.mEngineContext._Internal.ThreadScratchArenas.Deinit();
        }
        self.mSystems.Unregister(engine_context.Keep(), &self.mBodies);
        self.mTransactions.Unregister(engine_context.Keep(), &self.mBodies);
        self.mBodies.Deinit(engine_context);
        const leak_check = engine_context._Internal.KeepHeap.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
        try std.testing.expect(leak_check == .ok);
    }

    fn NewBody(self: *TestLayer, x: f32) !u32 {
        const engine_context = self.mEngineContext;
        const id = try self.mBodies.CreateEntity(engine_context.Keep());
        _ = try self.mBodies.AddComponent(engine_context, id, Position{ .x = x });
        return id;
    }

    fn NewLabel(self: *TestLayer, text: []const u8) !u32 {
        const engine_context = self.mEngineContext;
        const id = try self.mBodies.CreateEntity(engine_context.Keep());
        var label = Label{};
        try label.mText.appendSlice(engine_context.Keep(), text);
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

    _ = layer.mTransactions.RunTransaction(layer.mEngineContext, MovesTo5, .{ &layer.mBodies, id, &seen, true }, Keep);

    try std.testing.expectEqual(@as(f32, 5), seen.mOwnChange);
    try std.testing.expectEqual(@as(f32, 1), seen.mStorageDuring);
    try std.testing.expect(seen.mSameCopy);
    try std.testing.expectEqual(@as(f32, 5), layer.X(id));
    try std.testing.expect(layer.mTransactions.mOpenTransaction == null);
}

test "a change made in a transaction that isn't kept is dropped" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const id = try layer.NewBody(1);
    var seen: Seen = .{};

    _ = layer.mTransactions.RunTransaction(layer.mEngineContext, MovesTo5, .{ &layer.mBodies, id, &seen, false }, Keep);

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
    label.mText.appendSlice(engine_context.Keep(), " and more, enough to grow the list") catch unreachable;
    return keep;
}

test "a component that owns memory is deep copied: kept or dropped, nothing leaks and the other copy is untouched" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const engine_context = layer.mEngineContext;
    const kept = try layer.NewLabel("kept");
    const dropped = try layer.NewLabel("dropped");

    _ = layer.mTransactions.RunTransaction(engine_context, Appends, .{ &layer.mBodies, engine_context, kept, true }, Keep);
    _ = layer.mTransactions.RunTransaction(engine_context, Appends, .{ &layer.mBodies, engine_context, dropped, false }, Keep);

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

    _ = layer.mTransactions.RunTransaction(engine_context, AppendsThenRemoves, .{ &layer.mBodies, engine_context, id }, Keep);

    try std.testing.expect(!layer.mBodies.HasComponent(Label, id));
}

/// Moves the body to 5 inside a transaction of its own that says not to keep it, then hands back `keep`
fn MovesInsideAnother(transactions: *Transactions, engine_context: *EngineContext, bodies: *BodyECS, id: u32, keep: bool) bool {
    var seen: Seen = .{};
    _ = transactions.RunTransaction(engine_context, MovesTo5, .{ bodies, id, &seen, false }, Keep);
    return keep;
}

test "a transaction inside another is part of it, and goes or stays with it" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const engine_context = layer.mEngineContext;
    const kept = try layer.NewBody(1);
    const dropped = try layer.NewBody(1);

    _ = layer.mTransactions.RunTransaction(engine_context, MovesInsideAnother, .{ layer.mTransactions, engine_context, &layer.mBodies, kept, true }, Keep);
    _ = layer.mTransactions.RunTransaction(engine_context, MovesInsideAnother, .{ layer.mTransactions, engine_context, &layer.mBodies, dropped, false }, Keep);

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

    _ = layer.mTransactions.RunTransaction(engine_context, MovesAll, .{ &layer.mBodies, ids[0..], false }, Keep);
    _ = layer.mTransactions.RunTransaction(engine_context, MovesAll, .{ &layer.mBodies, ids[0..1], true }, Keep);

    try std.testing.expectEqual(@as(f32, 10), layer.X(ids[0]));
    try std.testing.expectEqual(@as(f32, 1), layer.X(ids[1]));
    try std.testing.expectEqual(@as(f32, 1), layer.X(ids[2]));
}

//----------------structural changes----------------

/// Makes a body with a position, a label and a child, and hands back `keep`
fn MakesBody(bodies: *BodyECS, engine_context: *EngineContext, made: *u32, child: *u32, keep: bool) bool {
    made.* = bodies.CreateEntity(engine_context.Keep()) catch unreachable;
    _ = bodies.AddComponent(engine_context, made.*, Position{ .x = 2 }) catch unreachable;
    var label = Label{};
    label.mText.appendSlice(engine_context.Keep(), "new") catch unreachable;
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

    _ = layer.mTransactions.RunTransaction(engine_context, MakesBody, .{ &layer.mBodies, engine_context, &made, &child, true }, Keep);

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

    _ = layer.mTransactions.RunTransaction(engine_context, MakesBody, .{ &layer.mBodies, engine_context, &made, &child, false }, Keep);

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
    label.mText.appendSlice(engine_context.Keep(), "added") catch unreachable;
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

    _ = layer.mTransactions.RunTransaction(engine_context, ChangesExisting, .{ &layer.mBodies, engine_context, kept, true }, Keep);
    _ = layer.mTransactions.RunTransaction(engine_context, ChangesExisting, .{ &layer.mBodies, engine_context, dropped, false }, Keep);

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

    _ = layer.mTransactions.RunTransaction(engine_context, MovesTags, .{ &layer.mBodies, engine_context, frozen, thawed, flicker, false }, Keep);

    try std.testing.expect(layer.mBodies.HasComponent(Frozen, frozen));
    try std.testing.expect(!layer.mBodies.HasComponent(Frozen, thawed));
    try std.testing.expect(!layer.mBodies.HasComponent(Frozen, flicker));

    _ = layer.mTransactions.RunTransaction(engine_context, MovesTags, .{ &layer.mBodies, engine_context, frozen, thawed, flicker, true }, Keep);

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

    _ = layer.mTransactions.RunTransaction(engine_context, AddsChild, .{ &layer.mBodies, engine_context, childless, false }, Keep);
    _ = layer.mTransactions.RunTransaction(engine_context, AddsChild, .{ &layer.mBodies, engine_context, parent, false }, Keep);

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

    pub fn Run(engine_context: *EngineContext, transactions: *Transactions, bodies: *BodyECS, before: u32, inside: u32) !void {
        try bodies.DestroyEntity(engine_context, before);
        _ = transactions.RunTransaction(engine_context, DestroysAndDrops, .{ bodies, engine_context, inside }, Keep);
    }
};

test "a transaction dropped inside a run only drops its own changes, not what the run queued before it" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const engine_context = layer.mEngineContext;
    const before = try layer.NewBody(1);
    const inside = try layer.NewBody(1);

    try layer.mSystems.RunSystem(QueuesThenDrops, engine_context, .{ layer.mTransactions, &layer.mBodies, before, inside });

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
fn AsksForActions(transactions: *Transactions, ran: *Ran, keep: bool) bool {
    const transaction = transactions.OpenTransaction().?;
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
    _ = layer.mTransactions.RunTransaction(engine_context, AsksForActions, .{ layer.mTransactions, &kept, true }, Keep);
    try std.testing.expectEqualStrings("ab", kept.mOrder[0..kept.mCount]);

    var dropped: Ran = .{};
    _ = layer.mTransactions.RunTransaction(engine_context, AsksForActions, .{ layer.mTransactions, &dropped, false }, Keep);
    try std.testing.expectEqualStrings("21", dropped.mOrder[0..dropped.mCount]);
}

//----------------the conflict report (what would conflict if a batch ran in parallel)----------------

const ConflictReport = @import("../../ECS/ConflictReport.zig");

/// What a stand-in hook does
const HookKind = enum { WritesPosition, ReadsPosition, AddsLabel, GroupsLabels, MakesBody };

const Hook = struct {
    mKind: HookKind,
    mID: u32 = 0,
    mKeep: bool = true,
};

fn RunsHook(bodies: *BodyECS, engine_context: *EngineContext, hook: Hook) bool {
    switch (hook.mKind) {
        .WritesPosition => bodies.GetComponentMut(Position, hook.mID).?.x = 9,
        .ReadsPosition => _ = bodies.GetComponent(Position, hook.mID).?.x,
        .AddsLabel => _ = bodies.AddComponent(engine_context, hook.mID, Label{}) catch unreachable,
        .GroupsLabels => {
            var group = bodies.GetGroup(engine_context.Keep(), .{ .Component = Label }) catch unreachable;
            group.deinit(engine_context.Keep());
        },
        .MakesBody => _ = bodies.CreateEntity(engine_context.Keep()) catch unreachable,
    }
    return hook.mKeep;
}

/// Runs each hook in a transaction of its own, one after another: a batch, the way a script loop runs its hooks
const TestBatch = struct {
    pub const Name = "TestBatch";

    pub fn Run(engine_context: *EngineContext, transactions: *Transactions, bodies: *BodyECS, hooks: []const Hook) void {
        for (hooks) |hook| _ = transactions.RunTransaction(engine_context, RunsHook, .{ bodies, engine_context, hook }, Keep);
    }
};

/// Runs `hooks` as one batch with measuring on, and hands back what the report says about it
fn Measured(layer: *TestLayer, hooks: []const Hook) !ConflictReport.Counts {
    const conflicts = &layer.mTransactions.mConflicts;
    conflicts.Clear(layer.mEngineContext.Keep());
    conflicts.mOn = true;
    defer conflicts.mOn = false;
    try layer.mSystems.RunSystem(TestBatch, layer.mEngineContext, .{ layer.mTransactions, &layer.mBodies, hooks });
    return conflicts.mSystems.get(TestBatch.Name) orelse .{};
}

test "a hook reading what an earlier hook in its batch changed would conflict, on that type" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const id = try layer.NewBody(1);

    const counts = try Measured(layer, &.{ .{ .mKind = .WritesPosition, .mID = id }, .{ .mKind = .ReadsPosition, .mID = id } });

    try std.testing.expectEqual(@as(u64, 1), counts.mBatches);
    try std.testing.expectEqual(@as(u64, 2), counts.mHooks);
    try std.testing.expectEqual(@as(u64, 1), counts.mConflicts);
    try std.testing.expectEqual(@as(usize, 1), counts.mTypes.count());
    try std.testing.expect(std.mem.endsWith(u8, counts.mTypes.keys()[0], "Position"));
}

test "hooks touching different entities, or reading before the write, would not conflict" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const a = try layer.NewBody(1);
    const b = try layer.NewBody(1);

    const apart = try Measured(layer, &.{ .{ .mKind = .WritesPosition, .mID = a }, .{ .mKind = .ReadsPosition, .mID = b } });
    try std.testing.expectEqual(@as(u64, 0), apart.mConflicts);

    const read_first = try Measured(layer, &.{ .{ .mKind = .ReadsPosition, .mID = a }, .{ .mKind = .WritesPosition, .mID = a } });
    try std.testing.expectEqual(@as(u64, 0), read_first.mConflicts);
}

test "a query after an add of the type it looks at would conflict" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const id = try layer.NewBody(1);

    const counts = try Measured(layer, &.{ .{ .mKind = .AddsLabel, .mID = id }, .{ .mKind = .GroupsLabels } });

    try std.testing.expectEqual(@as(u64, 1), counts.mConflicts);
}

test "a failed hook's writes don't count, and a hook that makes an object would run on its own" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const id = try layer.NewBody(1);

    const failed = try Measured(layer, &.{ .{ .mKind = .WritesPosition, .mID = id, .mKeep = false }, .{ .mKind = .ReadsPosition, .mID = id } });
    try std.testing.expectEqual(@as(u64, 0), failed.mConflicts);

    const made = try Measured(layer, &.{ .{ .mKind = .MakesBody }, .{ .mKind = .ReadsPosition, .mID = id } });
    try std.testing.expectEqual(@as(u64, 1), made.mSerial);
    try std.testing.expectEqual(@as(u64, 0), made.mConflicts);
}

test "with measuring off nothing is written down" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const id = try layer.NewBody(1);

    const hooks = [_]Hook{ .{ .mKind = .WritesPosition, .mID = id }, .{ .mKind = .ReadsPosition, .mID = id } };
    try layer.mSystems.RunSystem(TestBatch, layer.mEngineContext, .{ layer.mTransactions, &layer.mBodies, hooks[0..] });

    try std.testing.expectEqual(@as(usize, 0), layer.mTransactions.mConflicts.mSystems.count());
    try std.testing.expectEqual(@as(usize, 0), layer.mTransactions.mTransaction.mReads.count());
}

//----------------batches (Transactions.RunBatch): Aria on one thread----------------

/// What a batch hook does
const BatchKind = enum {
    /// adds 1 to the body's position, after reading it
    Increments,
    /// writes 9 to the body's position (handing it out to change counts as reading it too)
    WritesNine,
    /// reads the body's position, and writes down what it saw
    ReadsX,
    /// puts a label on the body
    Labels,
    /// writes down how many bodies have a label
    CountsLabels,
    /// puts Frozen on the body
    Freezes,
    /// writes down whether the body has Frozen
    SeesFrozen,
    /// makes a new body, which can't be done while speculating
    Makes,
    /// writes 5 to the body's position, then fails
    WritesThenFails,
    /// reads the body's position and writes it into mOther's
    CopiesX,
    /// writes down how it finds its transaction, and runs a system to see the run depth inside it
    Probes,
    /// takes memory from the scratch allocator
    FrameAllocates,
    /// waits for another Meets hook to be running at the same time (gArrived), giving up after a long while
    Meets,
};

/// How many Meets hooks have started
var gArrived: std.atomic.Value(u32) = .init(0);

const BatchHook = struct {
    mKind: BatchKind,
    mID: u32 = 0,
    /// how many times it has run, kept or not
    mRuns: u32 = 0,
    /// what it saw the last time it ran
    mSaw: f32 = 0,
    /// what Makes made, once it could
    mMade: ?u32 = null,
    /// CopiesX: the body written to
    mOther: u32 = 0,
    /// Probes: what it found
    mProbe: Probe = .{},
};

const Probe = struct {
    mParallel: bool = false,
    mOnWorker: bool = false,
    mOwnTransaction: bool = false,
    mDepthInHook: u32 = 0,
    mDepthInSystem: u32 = 0,
    mThread: std.Thread.Id = 0,
};

/// Writes down the run depth inside a run started from a hook
const DepthProbe = struct {
    pub const Name = "DepthProbe";

    pub fn Run(engine_context: *EngineContext, depth: *u32) void {
        depth.* = engine_context.mSystems.mRunDepth;
    }
};

fn RunsBatchHook(bodies: *BodyECS, engine_context: *EngineContext, hooks: []BatchHook, index: usize) bool {
    const hook = &hooks[index];
    hook.mRuns += 1;
    switch (hook.mKind) {
        .Increments => bodies.GetComponentMut(Position, hook.mID).?.x += 1,
        .WritesNine => bodies.GetComponentMut(Position, hook.mID).?.x = 9,
        .ReadsX => hook.mSaw = bodies.GetComponent(Position, hook.mID).?.x,
        .Labels => _ = bodies.AddComponent(engine_context, hook.mID, Label{}) catch unreachable,
        .CountsLabels => hook.mSaw = @floatFromInt(bodies.NumWithComponent(Label)),
        .Freezes => _ = bodies.AddComponent(engine_context, hook.mID, Frozen{}) catch unreachable,
        .SeesFrozen => hook.mSaw = if (bodies.HasComponent(Frozen, hook.mID)) 1 else 0,
        .Makes => hook.mMade = bodies.CreateEntity(engine_context.Keep()) catch |err| {
            std.debug.assert(err == error.RunSerially);
            return true;
        },
        .Probes => {
            const transactions = &engine_context.mTransactions;
            hook.mProbe.mParallel = transactions.mParallel;
            hook.mProbe.mOnWorker = transactions.OnWorker();
            hook.mProbe.mOwnTransaction = transactions.Current() != null and transactions.mOpenTransaction == null;
            hook.mProbe.mDepthInHook = engine_context.mSystems.mRunDepth;
            hook.mProbe.mThread = std.Thread.getCurrentId();
            engine_context.mSystems.RunSystem(DepthProbe, engine_context, .{&hook.mProbe.mDepthInSystem}) catch unreachable;
        },
        .FrameAllocates => _ = engine_context.Scratch().alloc(u8, 4096) catch unreachable,
        .Meets => {
            hook.mProbe.mThread = std.Thread.getCurrentId();
            _ = gArrived.fetchAdd(1, .acq_rel);
            var spins: u64 = 0;
            while (gArrived.load(.acquire) < 2 and spins < 4_000_000_000) : (spins += 1) std.atomic.spinLoopHint();
            //met: both were running at once
            hook.mSaw = if (gArrived.load(.acquire) >= 2) 1 else 0;
        },
        .CopiesX => {
            const x = bodies.GetComponent(Position, hook.mID).?.x;
            bodies.GetComponentMut(Position, hook.mOther).?.x = x;
        },
        .WritesThenFails => {
            bodies.GetComponentMut(Position, hook.mID).?.x = 5;
            return false;
        },
    }
    return true;
}

fn RunBatchOf(layer: *TestLayer, hooks: []BatchHook) !void {
    try layer.mTransactions.RunBatch(layer.mEngineContext, hooks.len, RunsBatchHook, .{ &layer.mBodies, layer.mEngineContext, hooks }, Keep);
}

test "hooks of a batch that touch different bodies all run once and are all kept" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const a = try layer.NewBody(1);
    const b = try layer.NewBody(1);
    var hooks = [_]BatchHook{ .{ .mKind = .Increments, .mID = a }, .{ .mKind = .Increments, .mID = b } };

    try RunBatchOf(layer, &hooks);

    try std.testing.expectEqual(@as(f32, 2), layer.X(a));
    try std.testing.expectEqual(@as(f32, 2), layer.X(b));
    try std.testing.expectEqual(@as(u32, 1), hooks[0].mRuns);
    try std.testing.expectEqual(@as(u32, 1), hooks[1].mRuns);
}

test "a hook doesn't see another's change while speculating, conflicts, and sees it when run again" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const a = try layer.NewBody(1);
    var hooks = [_]BatchHook{ .{ .mKind = .WritesNine, .mID = a }, .{ .mKind = .ReadsX, .mID = a } };

    try RunBatchOf(layer, &hooks);

    try std.testing.expectEqual(@as(u32, 2), hooks[1].mRuns);
    try std.testing.expectEqual(@as(f32, 9), hooks[1].mSaw);
    try std.testing.expectEqual(@as(f32, 9), layer.X(a));
}

test "hooks all changing one body come out as if run one after another: retried until each is kept" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const a = try layer.NewBody(0);
    var hooks = [_]BatchHook{ .{ .mKind = .Increments, .mID = a }, .{ .mKind = .Increments, .mID = a }, .{ .mKind = .Increments, .mID = a } };

    try RunBatchOf(layer, &hooks);

    try std.testing.expectEqual(@as(f32, 3), layer.X(a));
    try std.testing.expectEqual(@as(u32, 1), hooks[0].mRuns);
    try std.testing.expectEqual(@as(u32, 2), hooks[1].mRuns);
    try std.testing.expectEqual(@as(u32, 3), hooks[2].mRuns);
}

test "an add and a tag a hook holds aren't seen by the others until it is kept" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const a = try layer.NewBody(1);
    var hooks = [_]BatchHook{
        .{ .mKind = .Labels, .mID = a },
        .{ .mKind = .CountsLabels },
        .{ .mKind = .Freezes, .mID = a },
        .{ .mKind = .SeesFrozen, .mID = a },
    };

    try RunBatchOf(layer, &hooks);

    try std.testing.expectEqual(@as(u32, 2), hooks[1].mRuns);
    try std.testing.expectEqual(@as(f32, 1), hooks[1].mSaw);
    try std.testing.expectEqual(@as(u32, 2), hooks[3].mRuns);
    try std.testing.expectEqual(@as(f32, 1), hooks[3].mSaw);
    try std.testing.expect(layer.mBodies.HasComponent(Label, a));
    try std.testing.expect(layer.mBodies.HasComponent(Frozen, a));
}

test "a hook that makes an object is refused while speculating and run on its own after the rounds" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const a = try layer.NewBody(1);
    var hooks = [_]BatchHook{ .{ .mKind = .Makes }, .{ .mKind = .Increments, .mID = a } };

    try RunBatchOf(layer, &hooks);

    try std.testing.expectEqual(@as(u32, 2), hooks[0].mRuns);
    try std.testing.expect(layer.mBodies.IsActiveEntity(hooks[0].mMade.?));
    try std.testing.expectEqual(@as(f32, 2), layer.X(a));
}

test "a failed hook in a batch is dropped and not run again" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const a = try layer.NewBody(1);
    var hooks = [_]BatchHook{ .{ .mKind = .WritesThenFails, .mID = a }, .{ .mKind = .ReadsX, .mID = a } };

    try RunBatchOf(layer, &hooks);

    try std.testing.expectEqual(@as(u32, 1), hooks[0].mRuns);
    try std.testing.expectEqual(@as(u32, 1), hooks[1].mRuns);
    try std.testing.expectEqual(@as(f32, 1), hooks[1].mSaw);
    try std.testing.expectEqual(@as(f32, 1), layer.X(a));
}

test "two hooks writing the same thing without reading it conflict too: the later aborts (write after write)" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const a = try layer.NewBody(1);
    //putting a tag on reads nothing, it only writes
    var hooks = [_]BatchHook{ .{ .mKind = .Freezes, .mID = a }, .{ .mKind = .Freezes, .mID = a } };

    try RunBatchOf(layer, &hooks);

    try std.testing.expectEqual(@as(u32, 1), hooks[0].mRuns);
    try std.testing.expectEqual(@as(u32, 2), hooks[1].mRuns);
    try std.testing.expect(layer.mBodies.HasComponent(Frozen, a));
}

test "a hook that aborts still reserved what it wrote, so a later hook reading it aborts too (Aria's reservations)" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const a = try layer.NewBody(1);
    const b = try layer.NewBody(2);
    var hooks = [_]BatchHook{
        //writes a
        .{ .mKind = .WritesNine, .mID = a },
        //reads a, so aborts, but writes b first, which reserves b
        .{ .mKind = .CopiesX, .mID = a, .mOther = b },
        //reads b, reserved by the hook before it: aborts in round 1 although that hook wasn't kept, and again in round 2
        //when that hook is
        .{ .mKind = .ReadsX, .mID = b },
    };

    try RunBatchOf(layer, &hooks);

    try std.testing.expectEqual(@as(u32, 1), hooks[0].mRuns);
    try std.testing.expectEqual(@as(u32, 2), hooks[1].mRuns);
    try std.testing.expectEqual(@as(u32, 3), hooks[2].mRuns);
    //as if run in order: a is 9, copied into b, which the last one read
    try std.testing.expectEqual(@as(f32, 9), layer.X(b));
    try std.testing.expectEqual(@as(f32, 9), hooks[2].mSaw);
}

test "a batch's hooks find their own transactions through the per-thread lookup, and a run they start leaves the depth alone" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    var hooks = [_]BatchHook{ .{ .mKind = .Probes }, .{ .mKind = .Probes } };

    try RunBatchOf(layer, &hooks);

    for (hooks) |hook| {
        try std.testing.expect(hook.mProbe.mParallel);
        try std.testing.expect(hook.mProbe.mOnWorker);
        try std.testing.expect(hook.mProbe.mOwnTransaction);
        try std.testing.expect(hook.mProbe.mDepthInHook > 0);
        try std.testing.expectEqual(hook.mProbe.mDepthInHook, hook.mProbe.mDepthInSystem);
    }
    //and once the batch is done, nothing is open and nobody is a worker
    try std.testing.expect(!layer.mTransactions.mParallel);
    try std.testing.expect(!layer.mTransactions.OnWorker());
    try std.testing.expect(layer.mTransactions.Current() == null);
    try std.testing.expectEqual(@as(u32, 0), layer.mSystems.mRunDepth);
}

test "with no job pool, a batch's hooks take scratch memory from the engine's scratch arena, on the one thread there is" {
    const layer = try TestLayer.Init();
    defer layer.Deinit() catch unreachable;
    const engine_context = layer.mEngineContext;
    const shared_before = engine_context._Internal.ScratchArena.queryCapacity();
    var hooks = [_]BatchHook{ .{ .mKind = .FrameAllocates }, .{ .mKind = .FrameAllocates } };

    try RunBatchOf(layer, &hooks);

    try std.testing.expect(engine_context._Internal.ScratchArena.queryCapacity() >= shared_before + 4096);
}

//----------------the same batches on several threads----------------

test "on several threads, hooks touching different bodies all run once, and ones sharing a body still come out in order" {
    const layer = try TestLayer.InitThreaded(4);
    defer layer.Deinit() catch unreachable;
    const allocator = std.testing.allocator;

    //64 bodies a hook each, then 8 hooks all on one more
    var hooks: std.ArrayList(BatchHook) = .empty;
    defer hooks.deinit(allocator);
    var own: [64]u32 = undefined;
    for (&own) |*id| {
        id.* = try layer.NewBody(1);
        try hooks.append(allocator, .{ .mKind = .Increments, .mID = id.* });
    }
    const shared = try layer.NewBody(0);
    for (0..8) |_| try hooks.append(allocator, .{ .mKind = .Increments, .mID = shared });

    try RunBatchOf(layer, hooks.items);

    for (own, 0..) |id, ind| {
        try std.testing.expectEqual(@as(f32, 2), layer.X(id));
        try std.testing.expectEqual(@as(u32, 1), hooks.items[ind].mRuns);
    }
    try std.testing.expectEqual(@as(f32, 8), layer.X(shared));
    for (hooks.items[64..], 1..) |hook, runs| try std.testing.expectEqual(@as(u32, @intCast(runs)), hook.mRuns);
}

test "on several threads, write after write, reservations by hooks that abort, and the serial pass come out the same" {
    const layer = try TestLayer.InitThreaded(4);
    defer layer.Deinit() catch unreachable;

    const a = try layer.NewBody(1);
    var waw = [_]BatchHook{ .{ .mKind = .Freezes, .mID = a }, .{ .mKind = .Freezes, .mID = a } };
    try RunBatchOf(layer, &waw);
    try std.testing.expectEqual(@as(u32, 1), waw[0].mRuns);
    try std.testing.expectEqual(@as(u32, 2), waw[1].mRuns);

    const c = try layer.NewBody(1);
    const d = try layer.NewBody(2);
    var chain = [_]BatchHook{
        .{ .mKind = .WritesNine, .mID = c },
        .{ .mKind = .CopiesX, .mID = c, .mOther = d },
        .{ .mKind = .ReadsX, .mID = d },
    };
    try RunBatchOf(layer, &chain);
    try std.testing.expectEqual(@as(u32, 2), chain[1].mRuns);
    try std.testing.expectEqual(@as(u32, 3), chain[2].mRuns);
    try std.testing.expectEqual(@as(f32, 9), chain[2].mSaw);

    const e = try layer.NewBody(1);
    var serial = [_]BatchHook{ .{ .mKind = .Makes }, .{ .mKind = .Increments, .mID = e } };
    try RunBatchOf(layer, &serial);
    try std.testing.expectEqual(@as(u32, 2), serial[0].mRuns);
    try std.testing.expect(layer.mBodies.IsActiveEntity(serial[0].mMade.?));
    try std.testing.expectEqual(@as(f32, 2), layer.X(e));
}

test "on several threads, each hook has its own transaction, and runs it starts leave the depth alone" {
    const layer = try TestLayer.InitThreaded(4);
    defer layer.Deinit() catch unreachable;
    var hooks = [_]BatchHook{ .{ .mKind = .Probes }, .{ .mKind = .Probes }, .{ .mKind = .FrameAllocates }, .{ .mKind = .FrameAllocates } };
    try RunBatchOf(layer, &hooks);

    for (hooks[0..2]) |hook| {
        try std.testing.expect(hook.mProbe.mOnWorker);
        try std.testing.expect(hook.mProbe.mOwnTransaction);
        try std.testing.expectEqual(hook.mProbe.mDepthInHook, hook.mProbe.mDepthInSystem);
    }
    try std.testing.expect(!layer.mTransactions.mParallel);
}

test "on several threads, hooks of a batch really run side by side: two that each wait for the other both get through" {
    const layer = try TestLayer.InitThreaded(4);
    defer layer.Deinit() catch unreachable;
    gArrived = .init(0);
    var hooks = [_]BatchHook{ .{ .mKind = .Meets }, .{ .mKind = .Meets } };

    try RunBatchOf(layer, &hooks);

    try std.testing.expectEqual(@as(f32, 1), hooks[0].mSaw);
    try std.testing.expectEqual(@as(f32, 1), hooks[1].mSaw);
    try std.testing.expect(hooks[0].mProbe.mThread != hooks[1].mProbe.mThread);
}
