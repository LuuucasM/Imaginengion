//! What one transaction has changed so far, kept apart or written down until it ends: Commit keeps it, Discard drops it,
//! as if it never happened. The systems layer opens one around a piece of code (Systems.RunTransaction), which also
//! counts as a run, and while it is open every ECS the layer knows goes through it:
//!
//!   - Component values: GetComponentMut copies the component in here the first time (a deep copy for a type with a
//!     Clone) and hands back the copy, the same copy every time after. GetComponent hands back the copy if there is one,
//!     so the code sees what it has changed itself. Commit puts the copies in place, Discard drops them.
//!   - Queued changes (staged adds, removals, destroys): they wait in each ECS's queue as in any run. The first time the
//!     transaction queues into an ECS, the ECS writes down where its queue stood (NoteQueue), and Discard cuts it back
//!     to there.
//!   - Objects made (CreateEntity, CreateScript, AddChild): written down, and destroyed by Discard.
//!   - Tags put on or taken off, which happen right away: written down, and reversed by Discard.
//!   - Anything else: code outside the ECSs says what to do at commit (OnCommit, e.g. send an event it held back) or at
//!     discard (OnDiscard, e.g. put a script's variables back).
//!   - What can't be taken back at all (a file written, a popup's state): the code doing it marks the transaction
//!     (MarkIrrevocable), and a marked transaction is kept even when its code fails, rather than coming out half undone.
//!
//! Not held here: a staged component taken back off with RemoveComponentSync (gone for good), and a component staged
//! during the run, which is handed out as it is rather than copied.
const Transaction = @This();

const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const Tracy = @import("../Core/Tracy.zig");

/// The copies, in the order they were first made
mEntries: std.ArrayList(Entry) = .empty,
/// Where each copy is in mEntries, by what it is a copy of
mLookup: std.AutoHashMapUnmanaged(Key, usize) = .empty,
/// Where the copies themselves live, so a pointer handed out stays good until the transaction ends
mArena: std.heap.ArenaAllocator.State = .init,
/// The context the transaction was opened with (Open): GetComponentMut has none of its own to copy with
mEngineContext: ?*EngineContext = null,
/// Each ECS this transaction has queued changes in, in the order it first did, with where its queue stood before
mQueueMarks: std.ArrayList(QueueMark) = .empty,
/// The objects made in this transaction, oldest first
mCreated: std.ArrayList(Undo) = .empty,
/// The tags put on or taken off in this transaction, oldest first
mTagChanges: std.ArrayList(TagChange) = .empty,
/// What to do if the transaction is kept, in order
mOnCommit: std.ArrayList(Action) = .empty,
/// What to do if the transaction is dropped, newest first
mOnDiscard: std.ArrayList(Action) = .empty,
/// Why the transaction can't be dropped, null while it still can (MarkIrrevocable)
mIrrevocable: ?[]const u8 = null,

pub const empty: Transaction = .{};

/// Something to do when the transaction ends, with its data in the transaction's arena (OnCommit, OnDiscard)
pub const Action = struct {
    mData: *anyopaque,
    mRun: *const fn (engine_context: *EngineContext, data: *anyopaque) void,
};

/// What a copy is a copy of: one component array (a type in one ECS), and the entity in it
pub const Key = struct {
    mArray: *anyopaque,
    mEntityID: u64,
};

/// Puts a copy in place of the component in `array`, or deinitializes the copy if the component is gone by then.
/// Filled in for the copy's type by the array it came from (InternalComponentArray.CommitCopy)
pub const CommitFn = *const fn (array: *anyopaque, engine_context: *EngineContext, entity_id: u64, copy: *anyopaque) void;

const Entry = struct {
    mKey: Key,
    mCopy: *anyopaque,
    mCommit: CommitFn,
    mDiscard: *const fn (engine_context: *EngineContext, copy: *anyopaque) void,
};

/// Where one ECS's queue stood before this transaction queued into it, and what cuts it back to there
pub const QueueMark = struct {
    mECS: *anyopaque,
    mMark: usize,
    mDropFrom: *const fn (ecs: *anyopaque, engine_context: *EngineContext, mark: usize) void,
};

/// One object made, and what destroys it
pub const Undo = struct {
    mECS: *anyopaque,
    mEntityID: u64,
    mUndo: *const fn (ecs: *anyopaque, engine_context: *EngineContext, entity_id: u64) void,
};

/// One tag put on (`mAdded`) or taken off, and what reverses it
pub const TagChange = struct {
    mECS: *anyopaque,
    mEntityID: u64,
    mComponentInd: usize,
    mAdded: bool,
    mUndo: *const fn (ecs: *anyopaque, engine_context: *EngineContext, entity_id: u64, component_ind: usize, added: bool) void,
};

pub fn Deinit(self: *Transaction, engine_allocator: std.mem.Allocator) void {
    std.debug.assert(self._IsEmpty());
    self.mEntries.deinit(engine_allocator);
    self.mLookup.deinit(engine_allocator);
    self.mArena.promote(engine_allocator).deinit();
    self.mQueueMarks.deinit(engine_allocator);
    self.mCreated.deinit(engine_allocator);
    self.mTagChanges.deinit(engine_allocator);
    self.mOnCommit.deinit(engine_allocator);
    self.mOnDiscard.deinit(engine_allocator);
    self.* = .empty;
}

/// The copy of this component made in this transaction, null if there isn't one yet
pub fn Find(self: *const Transaction, key: Key) ?*anyopaque {
    // most of the time nothing has been copied, which keeps GetComponent from costing a lookup
    if (self.mEntries.items.len == 0) return null;
    const entry_ind = self.mLookup.get(key) orelse return null;
    return self.mEntries.items[entry_ind].mCopy;
}

/// Starts the transaction, which has to be empty
pub fn Open(self: *Transaction, engine_context: *EngineContext) void {
    std.debug.assert(self._IsEmpty());
    self.mEngineContext = engine_context;
}

/// Copies `source`, the component `key` names, into the transaction and hands back the copy. There mustn't be one already
pub fn Copy(self: *Transaction, key: Key, comptime T: type, source: *const T, commit: CommitFn) !*T {
    std.debug.assert(!self.mLookup.contains(key));
    const engine_context = self.mEngineContext.?;
    const engine_allocator = engine_context.EngineAllocator();
    try self.mEntries.ensureUnusedCapacity(engine_allocator, 1);
    try self.mLookup.ensureUnusedCapacity(engine_allocator, 1);

    var arena = self.mArena.promote(engine_allocator);
    defer self.mArena = arena.state;
    const copy = try arena.allocator().create(T);
    // a component that owns memory copies itself, so the copy can change it without touching the original's
    copy.* = if (@hasDecl(T, "Clone")) try source.Clone(engine_context) else source.*;

    self.mLookup.putAssumeCapacity(key, self.mEntries.items.len);
    self.mEntries.appendAssumeCapacity(.{
        .mKey = key,
        .mCopy = copy,
        .mCommit = commit,
        .mDiscard = struct {
            fn Discard(context: *EngineContext, erased: *anyopaque) void {
                const typed: *T = @ptrCast(@alignCast(erased));
                typed.Deinit(context);
            }
        }.Discard,
    });
    return copy;
}

/// Writes down where `ecs`'s queue stands, before the transaction first queues a change into it. Nothing the second time
pub fn NoteQueue(self: *Transaction, mark: QueueMark) !void {
    for (self.mQueueMarks.items) |noted| {
        if (noted.mECS == mark.mECS) return;
    }
    try self.mQueueMarks.append(self.mEngineContext.?.EngineAllocator(), mark);
}

/// Makes room to write down an object about to be made (AddCreated), so that once it is made writing it down can't fail
pub fn ReserveCreated(self: *Transaction) !void {
    try self.mCreated.ensureUnusedCapacity(self.mEngineContext.?.EngineAllocator(), 1);
}

/// Writes down an object just made, after ReserveCreated
pub fn AddCreated(self: *Transaction, created: Undo) void {
    self.mCreated.appendAssumeCapacity(created);
}

/// Makes room to write down a tag change about to be made (AddTagChange), so that once it is made writing it down can't fail
pub fn ReserveTagChange(self: *Transaction) !void {
    try self.mTagChanges.ensureUnusedCapacity(self.mEngineContext.?.EngineAllocator(), 1);
}

/// Writes down a tag change just made, after ReserveTagChange
pub fn AddTagChange(self: *Transaction, change: TagChange) void {
    self.mTagChanges.appendAssumeCapacity(change);
}

/// Runs `run(engine_context, &data)` if the transaction is kept, after the copies are in, in the order these were asked
/// for: for something code outside the ECSs holds back until then (an event it sends). `data` is copied into the
/// transaction's arena; a slice in it has to be too (Dupe)
pub fn OnCommit(self: *Transaction, data: anytype, comptime run: fn (*EngineContext, *@TypeOf(data)) void) !void {
    try self._AddAction(&self.mOnCommit, data, run);
}

/// Runs `run(engine_context, &data)` if the transaction is dropped, before anything else is undone, newest first: for
/// putting back something code outside the ECSs changed (a script's variables). `data` is copied as for OnCommit
pub fn OnDiscard(self: *Transaction, data: anytype, comptime run: fn (*EngineContext, *@TypeOf(data)) void) !void {
    try self._AddAction(&self.mOnDiscard, data, run);
}

/// A copy of `bytes` in the transaction's arena, good until the transaction ends: for an action's data with a slice in it
pub fn Dupe(self: *Transaction, bytes: []const u8) ![]u8 {
    var arena = self.mArena.promote(self.mEngineContext.?.EngineAllocator());
    defer self.mArena = arena.state;
    return try arena.allocator().dupe(u8, bytes);
}

/// Says the transaction has done something that can't be taken back, so it is kept even if its code fails: it never
/// comes out half undone. `reason` is for the log line saying so, and has to outlive the transaction (a string literal).
/// The first reason given is the one kept
pub fn MarkIrrevocable(self: *Transaction, reason: []const u8) void {
    if (self.mIrrevocable == null) self.mIrrevocable = reason;
}

fn _AddAction(self: *Transaction, list: *std.ArrayList(Action), data: anytype, comptime run: fn (*EngineContext, *@TypeOf(data)) void) !void {
    const T = @TypeOf(data);
    const engine_allocator = self.mEngineContext.?.EngineAllocator();
    try list.ensureUnusedCapacity(engine_allocator, 1);

    var arena = self.mArena.promote(engine_allocator);
    defer self.mArena = arena.state;
    const stored = try arena.allocator().create(T);
    stored.* = data;

    list.appendAssumeCapacity(.{ .mData = stored, .mRun = struct {
        fn Run(engine_context: *EngineContext, erased: *anyopaque) void {
            run(engine_context, @ptrCast(@alignCast(erased)));
        }
    }.Run });
}

/// Keeps everything: puts every copy in place of its component, in the order they were made, runs what was to happen
/// on commit, leaves what was queued to land with the run, and empties the transaction
pub fn Commit(self: *Transaction, engine_context: *EngineContext) void {
    const zone = Tracy.ZoneInit("Transaction::Commit", @src());
    defer zone.Deinit();
    zone.Value(self.mEntries.items.len);
    for (self.mEntries.items) |entry| entry.mCommit(entry.mKey.mArray, engine_context, entry.mKey.mEntityID, entry.mCopy);
    for (self.mOnCommit.items) |action| action.mRun(engine_context, action.mData);
    self._Reset(engine_context.EngineAllocator());
}

/// Drops everything, leaving the ECSs as they were before the transaction, and empties it. The order matters:
///   1. what was to happen on discard runs, newest first
///   2. objects made are destroyed, newest first, while what was staged on them can still be read by the removal hook
///   3. queued changes are cut back, newest ECS first, a staged add on a live object going through the removal hook
///   4. tag changes are reversed, newest first, skipping objects destroyed in 2
///   5. the copies are deinitialized
/// What was to happen on commit never does. Not for a transaction marked irrevocable, which can only be kept
pub fn Discard(self: *Transaction, engine_context: *EngineContext) void {
    std.debug.assert(self.mIrrevocable == null);
    const zone = Tracy.ZoneInit("Transaction::Discard", @src());
    defer zone.Deinit();
    zone.Value(self.mEntries.items.len);

    var action_ind = self.mOnDiscard.items.len;
    while (action_ind > 0) {
        action_ind -= 1;
        const action = self.mOnDiscard.items[action_ind];
        action.mRun(engine_context, action.mData);
    }

    var created_ind = self.mCreated.items.len;
    while (created_ind > 0) {
        created_ind -= 1;
        const created = self.mCreated.items[created_ind];
        created.mUndo(created.mECS, engine_context, created.mEntityID);
    }

    var mark_ind = self.mQueueMarks.items.len;
    while (mark_ind > 0) {
        mark_ind -= 1;
        const mark = self.mQueueMarks.items[mark_ind];
        mark.mDropFrom(mark.mECS, engine_context, mark.mMark);
    }

    var change_ind = self.mTagChanges.items.len;
    while (change_ind > 0) {
        change_ind -= 1;
        const change = self.mTagChanges.items[change_ind];
        change.mUndo(change.mECS, engine_context, change.mEntityID, change.mComponentInd, change.mAdded);
    }

    for (self.mEntries.items) |entry| entry.mDiscard(engine_context, entry.mCopy);
    self._Reset(engine_context.EngineAllocator());
}

fn _IsEmpty(self: *const Transaction) bool {
    return self.mEntries.items.len == 0 and self.mQueueMarks.items.len == 0 and self.mCreated.items.len == 0 and
        self.mTagChanges.items.len == 0 and self.mOnCommit.items.len == 0 and self.mOnDiscard.items.len == 0 and
        self.mIrrevocable == null;
}

fn _Reset(self: *Transaction, engine_allocator: std.mem.Allocator) void {
    self.mEngineContext = null;
    self.mEntries.clearRetainingCapacity();
    self.mLookup.clearRetainingCapacity();
    var arena = self.mArena.promote(engine_allocator);
    _ = arena.reset(.retain_capacity);
    self.mArena = arena.state;
    self.mQueueMarks.clearRetainingCapacity();
    self.mCreated.clearRetainingCapacity();
    self.mTagChanges.clearRetainingCapacity();
    self.mOnCommit.clearRetainingCapacity();
    self.mOnDiscard.clearRetainingCapacity();
    self.mIrrevocable = null;
}
